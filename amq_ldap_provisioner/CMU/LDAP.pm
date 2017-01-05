#Copyright 2014 Carnegie Mellon University
#All rights reserved.

#Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

#1. Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.

#2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.

#3. Neither the name of the copyright holder nor the names of its contributors may be used to endorse or promote products derived from this software without specific prior written permission.

#THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

#!/usr/bin/perl
package CMU::LDAP;
use Net::LDAPS;
use Log::Log4perl;
use Net::LDAP::Util
  qw(ldap_error_name ldap_error_text ldap_error_desc escape_filter_value);
use Data::Dumper;
use JSON;

require CMU::Stats;

my $log = Log::Log4perl->get_logger();

my $_binddn;
my $_password;
my $_port;
my $_server;
my $_syncou;
my $_peoplebase;
my $_groupobjectclass;
my $_personobjectclass;
my $_cache;
my $_env;
my $_memberattribute;
my $_dnattribute;
my $_memberprefix;
my $_groupprefix;
my $_logtoerrorqueue;
my $_amqmesg;
my $_ldap;

use strict;
use warnings;

sub new {
	my $class = shift;
	my $self  = {};
	bless $self, $class;
	return $self;
}

sub setAMQMessage {
	my ( $self, $mesg ) = @_;
	$log->debug("Calling CMU::LDAP::setAMQMessage(self, $mesg)");

	$self->{_amqmesg} = $mesg;
}

sub getLdapTargetName {
	my ($self) = @_;
	$log->debug("Calling CMU::LDAP::getLdapTargetName(self)");

	return $self->{_env};
}

sub getCache {
	my ($self) = @_;
	$log->debug("Calling CMU::LDAP::getCache(self)");

	return $self->{_cache};
}

sub getGroupMembers {
	my ( $self, $entry ) = @_;
	$log->debug("Calling CMU::LDAP::getGroupMembers( self, ldapentry)");

	my @members = ();
	push( @members, $entry->get_value( $self->{_memberattribute} ) );
	return @members;
}

sub getJsonErrorLdapUpdate {
	my ( $self, $result, $changetype, $ldif ) = @_;
	$log->debug(
"Calling CMU::LDAP::getJsonErrorLdapUpdate(self, ldapresult, $changetype, $ldif)"
	);

	$ldif =~ s/\n//g;
	my %err_hash = (
		'amqmesg'                => $self->{_amqmesg},
		'ldap_error_code'        => $result->code,
		'ldap_error_name'        => ldap_error_name( $result->code ),
		'ldap_error_description' => ldap_error_desc( $result->code ),
		'changetype'             => $changetype,
		'ldif'                   => $ldif
	);

	my $json = JSON::encode_json( \%err_hash );
	return $json;
}

sub getJsonErrorLdapEntry {
	my ( $self, $result, $filter ) = @_;
	$log->debug(
		"Calling CMU::LDAP::getJsonErrorLdapEntry(self, ldapresult, $filter)");

	my %err_hash = (
		'amqmesg'                => $self->{_amqmesg},
		'ldap_error_code'        => $result->code,
		'ldap_error_name'        => ldap_error_name( $result->code ),
		'ldap_error_description' => ldap_error_desc( $result->code ),
		'filter'                 => $filter
	);

	my $json = JSON::encode_json( \%err_hash );
	return $json;
}

sub getMemberDn {
	my ( $self, $memberuid ) = @_;
	$log->debug("Calling CMU::LDAP::getMemberDn(self, $memberuid)");

	my @attrs = ( $self->{_dnattribute} );
	my $result;
	my $dn = $self->{_cache}->get($memberuid);

	if ( defined $dn ) {
		return $dn;
	}

	if ( $memberuid =~ /:/ ) {
		$dn = $self->getGroupDn($memberuid);

		if ( !$self->checkGroupExists($dn) ) {
			undef $dn;
		}
	}
	else {
		eval {
			$result = $self->ldapSearch(
				"&("
				  . $self->{_memberprefix}
				  . $memberuid
				  . ")(objectClass="
				  . $self->{_personobjectclass} . ")",
				\@attrs, $self->{_peoplebase}
			);

			if ( $result->count < 1 ) {
				$log->info(
					"LDAP search didn't return result for uid " . $memberuid );
				return;
			}
			elsif ( $result->count == 1 ) {
				my $entry = $result->pop_entry();
				$dn = $entry->get_value( $self->{_dnattribute} );
				$self->{_cache}->set( $memberuid, $dn );
				$log->debug( "DN for " . $memberuid . " is " . $dn );
			}
			else {
				$log->error( "LDAP search returned more then 1 result for uid "
					  . $memberuid );
				die();
			}
		};
		if ($@) {
			$log->error( "CMU::LDAP::getMemberDn returned with error name: "
				  . ldap_error_name( $result->code )
				  . ", and error description: "
				  . ldap_error_desc( $result->code ) );
			die();
		}
	}
	return $dn;
}

sub removeGroupMember {
	my ( $self, $memberdn, $groupdn ) = @_;
	$log->debug(
		"Calling CMU::LDAP::removeGroupMember(self, $memberdn, $groupdn)");

	my $result;
	my @attrs = ( $self->{_dnattribute});
	my $entry =
	  $self->getLdapEntry( "&(" . $self->{_memberattribute} . "=" . escape_filter_value($memberdn) . ")",
		\@attrs, $groupdn );

	if ( defined $entry ) {
		$entry->delete( $self->{_memberattribute} => [$memberdn] );

		my $result = $self->ldapUpdate($entry);

		if ( $result->code ) {
			if ( ldap_error_name( $result->code ) eq "LDAP_NO_SUCH_ATTRIBUTE" ) {
				$log->info( "member "
					  . $memberdn
					  . " doesn't exist already in "
					  . $groupdn );
			}
			else {
				$log->error(
					"CMU::LDAP::removeGroupMember returned with error name: "
					  . ldap_error_name( $result->code )
					  . ", error description: "
					  . ldap_error_desc( $result->code )
					  . ", changetype: "
					  . $entry->changetype()
					  . ", ldif: "
					  . $entry->ldif() );
				die();
			}
		}
		else {
			$log->info( "members "
				  . $memberdn
				  . " sucessfully deleted from "
				  . $groupdn );
		}
	}
	else {
		$log->info(
			    "Skipping removeGroupMember as ldapentry not found with member "
			  . $memberdn
			  . " in group "
			  . $groupdn );
	}
	return $result;

}

sub checkGroupExists {
	my ( $self, $dn ) = @_;
	$log->debug("Calling CMU::LDAP::checkGroupExists(self, $dn)");

	my @attrs = ( $self->{_dnattribute} );

	my $result =
	  $self->ldapSearch( "(objectClass=" . $self->{_groupobjectclass} . ")",
		\@attrs, $dn );

	if ( $result->code ) {
		if ( ldap_error_name( $result->code ) eq "LDAP_NO_SUCH_OBJECT" ) {
			$log->debug( "Not found " . $dn );
		}
		else {
			my $errdesc = ldap_error_desc( $result->code );
			$log->error(
				    "CMU::LDAP::checkGroupExists returned with error name: "
				  . ldap_error_name( $result->code )
				  . ", and error description: "
				  . ldap_error_desc( $result->code ) );
			die();
		}
	}

	if ( $result->count() ) {
		$log->debug( "Found " . $dn );
	}
	else {
		$log->debug( "Not found " . $dn );
	}

	return $result->count();
}

sub checkOUExists {
	my ( $self, $dn ) = @_;
	$log->debug("Calling CMU::LDAP::checkOUExists(self, $dn)");

	my @attrs = ( $self->{_dnattribute} );

	my $result =
	  $self->ldapSearch( "(objectClass=organizationalUnit)", \@attrs, $dn );

	if ( $result->code ) {
		if ( ldap_error_name( $result->code ) eq "LDAP_NO_SUCH_OBJECT" ) {
			$log->debug( "Not found " . $dn );
		}
		else {
			my $errdesc = ldap_error_desc( $result->code );
			$log->error( "CMU::LDAP::checkOUExists returned with error name: "
				  . ldap_error_name( $result->code )
				  . ", and error description: "
				  . ldap_error_desc( $result->code ) );
			die();
		}
	}

	if ( $result->count() ) {
		$log->debug( "Found " . $dn );
	}
	else {
		$log->debug( "Not found " . $dn );
	}

	return $result->count();
}

sub addGroupDescription {
	my ( $self, $dn, $description ) = @_;
	$log->debug(
		"Calling CMU::LDAP::addGroupDescription(self, $dn, $description)");

	my $result;
	my @attrs = ( $self->{_dnattribute} );
	my $entry =
	  $self->getLdapEntry( "(objectClass=" . $self->{_groupobjectclass} . ")",
		\@attrs, $dn );
	if ( defined $entry ) {
		$entry->add( 'description' => $description );

		$result = $self->ldapUpdate($entry);

		if ( $result->code ) {
			if ( ldap_error_name( $result->code ) eq
				"LDAP_TYPE_OR_VALUE_EXISTS" )
			{
				$log->info( $description . " already exists for group " .  $dn );
			}
			else {
				$log->error(
					"CMU::LDAP::addGroupDescription returned with error name: "
					  . ldap_error_name( $result->code )
					  . ", error description: "
					  . ldap_error_desc( $result->code )
					  . ", changetype: "
					  . $entry->changetype()
					  . ", ldif: "
					  . $entry->ldif() );
				die();
			}
		}
		else {
			$log->info(
				"Added description " . $description . " for group " . $dn );
		}
	}
	else {
		$log->info(
			"Skipping addGroupDescription as ldapentry not found for group "
			  . $dn );
	}
	return $result;
}

sub removeGroupDescription {
	my ( $self, $dn, $description ) = @_;
	$log->debug(
		"Calling CMU::LDAP::removeGroupDescription(self, $dn, $description)");

	my $result;
	my @attrs = ( $self->{_dnattribute} );
	my $entry =
	  $self->getLdapEntry( "(objectClass=" . $self->{_groupobjectclass} . ")",
		\@attrs, $dn );
	if ( defined $entry ) {
		$entry->delete( 'description' => $description );

		$result = $self->ldapUpdate($entry);

		if ( $result->code ) {
			if ( ldap_error_name( $result->code ) eq
				"LDAP_TYPE_OR_VALUE_EXISTS" )
			{
				$log->info( $description . " already exists for group " .  $dn);
			}
			else {

				$log->error(
"CMU::LDAP::removeGroupDescription returned with error name: "
					  . ldap_error_name( $result->code )
					  . ", error description: "
					  . ldap_error_desc( $result->code )
					  . ", changetype: "
					  . $entry->changetype()
					  . ", ldif: "
					  . $entry->ldif() );
				die();
			}
		}
		else {
			$log->info(
				"Removed description " . $description . " for group " . $dn );
		}
	}
	else {
		$log->info(
			"Skipping removeGroupDescription as ldapentry not found for group "
			  . $dn );
	}
	return $result;
}

sub replaceGroupDescription {
	my ( $self, $dn, $description ) = @_;
	$log->debug(
		"Calling CMU::LDAP::replaceGroupDescription(self, $dn, $description)");

	my $result;
	my @attrs = ( $self->{_dnattribute} );
	my $entry =
	  $self->getLdapEntry( "(objectClass=" . $self->{_groupobjectclass} . ")",
		\@attrs, $dn );
	if ( defined $entry ) {
		$entry->replace( 'description' => $description );

		my $result = $self->ldapUpdate($entry);

		if ( $result->code ) {
			if ( ldap_error_name( $result->code ) eq
				"LDAP_TYPE_OR_VALUE_EXISTS" )
			{
				$log->info( $description . " already exists for group " .  $dn );
			}
			else {
				$log->error(
"CMU::LDAP::replaceGroupDescription returned with error name: "
					  . ldap_error_name( $result->code )
					  . ", error description: "
					  . ldap_error_desc( $result->code )
					  . ", changetype: "
					  . $entry->changetype()
					  . ", ldif: "
					  . $entry->ldif() );
				die();
			}
		}
		else {
			$log->info( "Replaced description with "
				  . $description
				  . " for group "
				  . $dn );
		}
	}
	else {
		$log->info(
			"Skipping replaceGroupDescription as ldapentry not found for group "
			  . $dn );
	}

	return $result;
}

sub addGroupMember {
	my ( $self, $memberdn, $groupdn ) = @_;
	$log->debug("Calling CMU::LDAP::addGroupMember(self, $memberdn, $groupdn)");

	my $result;
	my @attrs = ( $self->{_dnattribute});
	my $entry =
	  $self->getLdapEntry( "!(" . $self->{_memberattribute} . "=" . escape_filter_value($memberdn) . ")",
		\@attrs, $groupdn );

	if ( defined $entry ) {
		$entry->add( $self->{_memberattribute} => [$memberdn] );

		$result = $self->ldapUpdate($entry);

		if ( $result->code ) {
			if ( ldap_error_name( $result->code ) eq "LDAP_ALREADY_EXISTS" ) {
				$log->info(
					"member " . $memberdn . " already exists in " . $groupdn );
			}
			else {
				$log->error(
					    "CMU::LDAP::addGroupMember returned with error name: "
					  . ldap_error_name( $result->code )
					  . ", error description: "
					  . ldap_error_desc( $result->code )
					  . ", changetype: "
					  . $entry->changetype()
					  . ", ldif: "
					  . $entry->ldif() );
				die();
			}
		}
		$log->info(
			"member " . $memberdn . " sucessfully added to " . $groupdn );
	}
	else {
		$log->info(
			    "Skipping addGroupMember as ldapentry not found with member "
			  . $memberdn
			  . " not in group "
			  . $groupdn );
	}
	return $result;
}

sub bulkGroupMemberAdd {
	my ( $self, $memberdn, $groupdn ) = @_;
	$log->debug(
		"Calling CMU::LDAP::bulkGroupMemberAdd(self, memberdn, $groupdn)");

	my $result;
	my @attrs = ( $self->{_dnattribute});
	my $entry =
	  $self->getLdapEntry( "(objectClass=" . $self->{_groupobjectclass} . ")",
		\@attrs, $groupdn );

	if ( defined $entry ) {
		$entry->add( $self->{_memberattribute} => [@$memberdn]);

		$result = $self->ldapUpdate($entry);
		my $out = Dumper $memberdn;
		if ( $result->code ) {
			if (   ldap_error_name( $result->code ) eq "LDAP_ALREADY_EXISTS"
				|| ldap_error_name( $result->code ) eq
				"LDAP_TYPE_OR_VALUE_EXISTS" )
			{
				$log->info(
					"member " . $out . " already exists in " . $groupdn );
			}
			else {
				$log->error(
					"CMU::LDAP::bulkGroupMemberAdd returned with error name: "
					  . ldap_error_name( $result->code )
					  . ", error description: "
					  . ldap_error_desc( $result->code )
					  . ", changetype: "
					  . $entry->changetype()
					  . ", ldif: "
					  . $entry->ldif() );
			}
		}
		else {
			$log->info(
				"members " . $out . " sucessfully added to " . $groupdn );
		}
	}
	else {
		$log->info(
			"Skipping bulkGroupMemberAdd as ldapentry not found for group "
			  . $groupdn );
	}
	return $result;
}

sub bulkGroupMemberRemove {
	my ( $self, $memberdn, $groupdn ) = @_;
	$log->debug(
		"Calling CMU::LDAP::bulkGroupMemberRemove(self, memberdn, $groupdn)");

	my $result;
	my @attrs = ( $self->{_dnattribute});
	my $entry =
	  $self->getLdapEntry( "(objectClass=" . $self->{_groupobjectclass} . ")",
		\@attrs, $groupdn );

	if ( defined $entry ) {
		$entry->delete( $self->{_memberattribute} => [@$memberdn] );

		my $result = $self->ldapUpdate($entry);
		my $out    = Dumper $memberdn;

		if ( $result->code ) {
			if ( ldap_error_name( $result->code ) eq "LDAP_NO_SUCH_OBJECT" ) {
				$log->info( "member " . $out
					  . " doesn't exist already in "
					  . $groupdn );
			}
			else {
				$log->error(
"CMU::LDAP::bulkGroupMemberRemove returned with error name: "
					  . ldap_error_name( $result->code )
					  . ", and error description: "
					  . ldap_error_desc( $result->code ) );
				die();
			}
		}
		else {
			$log->info(
				"member " . $out . "sucessfully removed from " . $groupdn );
		}
	}
	else {
		$log->info(
			"Skipping bulkGroupMemberRemove as ldapentry not found for group "
			  . $groupdn );
	}
	return $result;
}

sub isConnected {
	my ($self) = @_;
	$log->debug("Calling CMU::LDAP::isConnected(self)");

	return $self->{_ldap}->socket->connected();
}

sub ldapUpdate {
	my ( $self, $entry ) = @_;
	$log->debug("Calling CMU::LDAP::ldapUpdate(self)");

	my $result = $entry->update( $self->{_ldap} );

	if ( $result->code ) {
		$log->info( "changetype: "
			  . $entry->changetype()
			  . ", ldif:"
			  . $entry->ldif() );

		if ( $self->{_logtoerrorqueue} ) {
			my $json_error =
			  $self->getJsonErrorLdapUpdate( $result, $entry->changetype(),
				$entry->ldif() );

			my $activemq = CMU::ActiveMQ->new();

			if ( defined $activemq ) {
				$activemq->sendToErrorQueue($json_error);
			}
		}
	}

	my $ldiflog = Log::Log4perl->get_logger("389.LDIF");

	if ( defined $ldiflog ) {
		$ldiflog->info( "changetype: "
			  . $entry->changetype()
			  . ", ldif:"
			  . $entry->ldif() );
	}

	if ( $entry->changetype() eq "add" ) {
		CMU::Stats::incrementStat("ldap_num_adds");
	}
	elsif ( $entry->changetype() eq "modify" ) {
		CMU::Stats::incrementStat("ldap_num_modify");
	}
	elsif ( $entry->changetype() eq "delete" ) {
		CMU::Stats::incrementStat("ldap_num_deletes");
	}

	return $result;
}

sub connect {
	my ($self) = @_;
	$log->debug("Calling CMU::LDAP::connect(self)");

	eval {
		$self->{_ldap} =
		  Net::LDAPS->new( $self->{_server}, port => $self->{_port} );
	};
	if ($@) {
		$log->error("Could not create LDAP object because:$!");
		return;
	}

	my $result =
	  $self->{_ldap}->bind( $self->{_binddn}, password => $self->{_password} );

	if ( $result->code ) {
		$log->error( "CMU::LDAP::connect returned with error name: "
			  . ldap_error_name( $result->code )
			  . ", and error description: "
			  . ldap_error_desc( $result->code ) );
		return;
	}
	else {
		$log->info("Bind sucessful");
	}
}

sub ldapSearch {
	my ( $self, $searchstring, $attrs, $base ) = @_;

	$log->debug(
		"Calling CMU::LDAP::ldapSearch(self, $searchstring, attrs, $base)");

	my $result = $self->{_ldap}->search(
		base   => $base,
		scope  => "sub",
		filter => $searchstring,
		attrs  => $attrs
	);

	CMU::Stats::incrementStat("ldap_num_searches");

	if ($result) {
		if ( ldap_error_name( $result->code ) eq "LDAP_SUCCESS" ) {
			$log->debug( "Ldap search successfull for "
				  . $searchstring . " and "
				  . $base );
		}
		elsif ( ldap_error_name( $result->code ) eq "LDAP_NO_SUCH_OBJECT" ) {
			$log->info( "Ldap search didn't return result for filter "
				  . $searchstring
				  . " and base "
				  . $base );
		}
		elsif ( ldap_error_name( $result->code ) eq "LDAP_LOCAL_ERROR" ) {
			$log->info( "CMU::LDAP::search returned with error name: "
				  . ldap_error_name( $result->code )
				  . ", and error description: "
				  . ldap_error_desc( $result->code ) );
				  die();
		}
		else {
			$log->error( "CMU::LDAP::search returned with error name: "
				  . ldap_error_name( $result->code )
				  . ", and error description: "
				  . ldap_error_desc( $result->code ) );
			die();
		}
	}
	return $result;
}

sub createOU {
	my ( $self, $dn ) = @_;
	$log->debug("Calling CMU::LDAP::createOU(self, $dn)");

	my $entry = Net::LDAP::Entry->new($dn);
	$entry->add( 'objectClass' => [ 'top', 'organizationalUnit' ] );

	my $result = $self->ldapUpdate($entry);

	if ( $result->code ) {
		if ( ldap_error_name( $result->code ) eq "LDAP_ALREADY_EXISTS" ) {
			$log->info( "LDAP OU " . $dn . " already exists" );
		}
		else {
			$log->error( "CMU::LDAP::::createOU returned with error name: "
				  . ldap_error_name( $result->code )
				  . ", error description: "
				  . ldap_error_desc( $result->code )
				  . ", changetype: "
				  . $entry->changetype()
				  . ", ldif: "
				  . $entry->ldif() );
			die();
		}
	}
	else {
		$log->info( "Created LDAP OU " . $dn );
	}

	return $result;
}

sub getLdapEntry {
	my ( $self, $filter, $attrs, $dn ) = @_;
	$log->debug("Calling CMU::LDAP::getLdapEntry(self, $filter, attrs, $dn)");

	my $entry;
	my $result = $self->ldapSearch( $filter, $attrs, $dn );

	if ( $result->code ) {
		if ( ldap_error_name( $result->code ) eq "LDAP_NO_SUCH_OBJECT" ) {
			$log->debug("Not found dn: $dn");
		}
		else {
			$log->error( "CMU::LDAP::getLdapEntry returned with error name: "
				  . ldap_error_name( $result->code )
				  . ", and error description: "
				  . ldap_error_desc( $result->code ) );
			die();
		}
	}
	else {
		#$entry = $result->pop_entry();
		#$entry = $result->entry(0);
		while ($entry = $result->pop_entry()){
			$log->debug("Heres the entry dn: ");
			$log->debug($entry->dn);
			$log->debug($dn);
			if ( lc $entry->dn eq lc $dn) {
				$log->debug ("The entry has the proper dn: $dn");
				last;
			} else {
			 	$log->debug ("This dn isn't it: $entry->dn");
				$entry = undef;
			}
		}

		if ( defined $entry ) {
			my $entrydn = $entry->get_value( $self->{_dnattribute} );
			$log->debug( "LDAPEntry found for filter: " . $filter
				  . " and basedn "
				  . $dn );
		}
		else {
			$log->error( "LDAPEntry not found for filter: " . $filter
				  . " and basedn "
				  . $dn );
		}
	}

	return $entry;
}

sub deleteObject {
	my ( $self, $dn ) = @_;
	$log->debug("Calling CMU::LDAP::objectDelete(self, $dn)");

	my $result;
	my @attrs = ( $self->{_dnattribute} );
	my $entry = $self->getLdapEntry( "(objectClass=*)", \@attrs, $dn );

	if ( defined $entry ) {
		$entry->delete();
		$result = $self->ldapUpdate($entry);

		if ( $result->code ) {
			if ( ldap_error_name( $result->code ) eq "LDAP_NO_SUCH_OBJECT" ) {
				$log->info( "Couldn't find object " . $dn . " to delete" );
				return 0;
			}
			else {
				$log->error(
					    "CMU::LDAP::objectDelete returned with error name: "
					  . ldap_error_name( $result->code )
					  . ", error description: "
					  . ldap_error_desc( $result->code )
					  . ", changetype: "
					  . $entry->changetype()
					  . ", ldif: "
					  . $entry->ldif() );
				die();
			}
		}
		else {
			$log->info( "Sucessfully deleted " . $dn );
		}
	}
	else {
		$log->info( "Skipping deleteObject as ldapentry not found for " . $dn );
	}
	return $result;
}

1;
