#Copyright 2014 Carnegie Mellon University
#All rights reserved.

#Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

#1. Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.

#2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.

#3. Neither the name of the copyright holder nor the names of its contributors may be used to endorse or promote products derived from this software without specific prior written permission.

#THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

package CMU::LDAP::389;

use Net::LDAP::Util
  qw(ldap_error_name ldap_error_text ldap_error_desc ldap_explode_dn escape_filter_value escape_dn_value );
use Net::LDAP::Entry;
use base ("CMU::LDAP");
use Net::LDAPS;
use Data::Dumper;
use strict;
use warnings;

require CMU::CFG;
require CMU::Cache;
require CMU::Stats;

my $_389;
my $_cn;

my $log = Log::Log4perl->get_logger();

sub getInstance {
	$log->debug("Calling CMU::LDAP::389::getInstance(self)");
	if ( !defined $_389 ) {
		my $class = shift;
		my $self  = {};
		$_389 = bless $self, $class;

		CMU::CFG::readConfig('configuration.pl');

		$_389->{_server}           = $CMU::CFG::_CFG{'389'}{'server'};
		$_389->{_port}           = $CMU::CFG::_CFG{'389'}{'port'};
		$_389->{_binddn}           = $CMU::CFG::_CFG{'389'}{'binddn'};
		$_389->{_password}         = $CMU::CFG::_CFG{'389'}{'password'};
		$_389->{_syncou}           = $CMU::CFG::_CFG{'389'}{'syncou'};
		$_389->{_peoplebase}       = $CMU::CFG::_CFG{'389'}{'peoplebase'};
		$_389->{_server}           = $CMU::CFG::_CFG{'389'}{'server'};
		$_389->{_groupobjectclass} = $CMU::CFG::_CFG{'389'}{'groupobjectclass'};
		$_389->{_personobjectclass} =
		  $CMU::CFG::_CFG{'389'}{'personobjectclass'};
		$_389->{_memberattribute}  = $CMU::CFG::_CFG{'389'}{'memberattribute'};
		$_389->{_dnattribute}     = $CMU::CFG::_CFG{'389'}{'dnattribute'};
		$_389->{_memberprefix}    = $CMU::CFG::_CFG{'389'}{'memberprefix'};
		$_389->{_groupprefix}    = $CMU::CFG::_CFG{'389'}{'groupprefix'};
		$_389->{_env}             = $CMU::CFG::_CFG{'ldap'}{'env'};
		$_389->{_logtoerrorqueue} = $CMU::CFG::_CFG{'ldap'}{'logtoerrorqueue'};
		$_389->{_cache}           = CMU::Cache->new;
		$_389->connect();
	}

	return $_389;
}

sub connect {

	my ($self) = @_;
	$log->debug("Calling CMU::LDAP::389::connect(self)");
	$log->debug($self->{_server});
	$log->debug($self->{_port});
	$log->debug($self->{_binddn});
	
	

	eval {
		$self->{_ldap} =
		  	Net::LDAPS->new( $self->{_server}, port => $self->{_port} );
			$log->debug("after LDAP call");
			#my $mesg = $self->{_ldap}->start_tls();
			#$log->debug("The result is: $mesg->code");
			#$log->debug("At the end of eval");
		
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

	$log->info("Bind sucessful");
	return;
}

sub disconnect {
	my ($self) = @_;

	$log->debug("Calling CMU::LDAP::389::disconnect(self)");

	if ( defined $self->{_ldap} ) {
		eval { $self->{_ldap}->unbind; };

		if ($@) {
			$log->error("Could not unbind LDAP because:$!");
		}
		undef $self->{_ldap};
	}

	undef $_389;
}

sub getGroupOwners {
	my ( $self, $entry ) = @_;
	$log->debug("Calling CMU::LDAP::getGroupOwners( self, ldapentry)");

	my @owners = ();
	push( @owners, $entry->get_value("owner") );
	return @owners;
}

sub addGroupOwner {
	my ( $self, $memberdn, $groupdn ) = @_;
	$log->debug("Calling CMU::LDAP::addGroupOwner(self, $memberdn, $groupdn)");

	my $result;
	my @attrs = ( $self->{_dnattribute});
	my $entry =
	  $self->getLdapEntry( "!(owner=" . escape_filter_value($memberdn) . ")",
		\@attrs, $groupdn );

	if ( defined $entry ) {
		$entry->add( 'owner' => [$memberdn] );

		$result = $self->ldapUpdate($entry);

		if ( $result->code ) {
			if ( ldap_error_name( $result->code ) eq "LDAP_ALREADY_EXISTS" ) {
				$log->info(
					"owner " . $memberdn . " already exists in " . $groupdn );
			}
			else {
				$log->error(
					    "CMU::LDAP::addGroupOwner returned with error name: "
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
			"owner " . $memberdn . " sucessfully added to " . $groupdn );
	}
	else {
		$log->info(
			    "Skipping addGroupOwner as ldapentry not found with owner "
			  . $memberdn
			  . " not in group "
			  . $groupdn );
	}
	return $result;
}

sub bulkGroupOwnerAdd {
	my ( $self, $ownerdn, $groupdn ) = @_;
	$log->debug(
		"Calling CMU::LDAP::bulkGroupOwnerAdd(self, ownerdn, $groupdn)");

	my $result;
	my @attrs = ( $self->{_dnattribute} );
	my $entry =
	  $self->getLdapEntry( "(objectClass=" . $self->{_groupobjectclass} . ")",
		\@attrs, $groupdn );

	if ( defined $entry ) {
		$entry->add( 'owner' => [@$ownerdn] );

		$result = $self->ldapUpdate($entry);
		my $out = Dumper $ownerdn;
		if ( $result->code ) {
			if (   ldap_error_name( $result->code ) eq "LDAP_ALREADY_EXISTS"
				|| ldap_error_name( $result->code ) eq
				"LDAP_TYPE_OR_VALUE_EXISTS" )
			{
				$log->info(
					"owner " . $out . " already exists in " . $groupdn );
			}
			else {
				$log->error(
					"CMU::LDAP::bulkGroupOwnerAdd returned with error name: "
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
				"owners " . $out . " sucessfully added to " . $groupdn );
		}
	}
	else {
		$log->info(
			"Skipping bulkGroupOwnerAdd as ldapentry not found for group "
			  . $groupdn );
	}
	return $result;
}

sub bulkGroupOwnerRemove {
	my ( $self, $ownerdn, $groupdn ) = @_;
	$log->debug(
		"Calling CMU::LDAP::bulkGroupOwnerRemove(self, ownerdn, $groupdn)");

	my $result;
	my @attrs = ( $self->{_dnattribute} );
	my $entry =
	  $self->getLdapEntry( "(objectClass=" . $self->{_groupobjectclass} . ")",
		\@attrs, $groupdn );

	if ( defined $entry ) {
		$entry->delete( 'owner' => [@$ownerdn] );

		my $result = $self->ldapUpdate($entry);
		my $out    = Dumper $ownerdn;

		if ( $result->code ) {
			if ( ldap_error_name( $result->code ) eq "LDAP_NO_SUCH_OBJECT" ) {
				$log->info( "member " . $out
					  . " doesn't exist already in "
					  . $groupdn );
			}
			else {
				$log->error(
"CMU::LDAP::bulkGroupOwnerRemove returned with error name: "
					  . ldap_error_name( $result->code )
					  . ", and error description: "
					  . ldap_error_desc( $result->code ) );
				die();
			}
		}
		else {
			$log->info(
				"owner " . $out . "sucessfully removed from " . $groupdn );
		}
	}
	else {
		$log->info(
			"Skipping bulkGroupOwnerRemove as ldapentry not found for group "
			  . $groupdn );
	}
	return $result;
}


sub removeGroupOwner {
	my ( $self, $memberdn, $groupdn ) = @_;
	$log->debug(
		"Calling CMU::LDAP::removeGroupOwner(self, $memberdn, $groupdn)");

	my $result;
	my @attrs = ( $self->{_dnattribute});
	my $entry =
	  $self->getLdapEntry( "&(owner=" . escape_filter_value($memberdn) . ")",
		\@attrs, $groupdn );

	if ( defined $entry ) {
		$entry->delete( 'owner' => [$memberdn] );

		my $result = $self->ldapUpdate($entry);

		if ( $result->code ) {
			if ( ldap_error_name( $result->code ) eq "LDAP_NO_SUCH_ATTRIBUTE" ) {
				$log->info( "owner "
					  . $memberdn
					  . "doesn't exist already in "
					  . $groupdn );
			}
			else {
				$log->error(
					"CMU::LDAP::removeGroupOwner returned with error name: "
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
			$log->info( "owner "
				  . $memberdn
				  . " sucessfully deleted from "
				  . $groupdn );
		}
	}
	else {
		$log->info(
			    "Skipping removeGroupOwner as ldapentry not found with owner "
			  . $memberdn
			  . " in group "
			  . $groupdn );
	}
	return $result;
}

sub createGroup {
	my ( $self, $dn, $description ) = @_;
	$log->debug("Calling CMU::LDAP::389::createGroup(self, $dn)");

	my $entry = Net::LDAP::Entry->new($dn);
	my $cn    = $self->{_amqmesg}->{"name"};

	if ( defined $description && $description ne '' ) {
		$entry->add(
			'objectClass' => [ 'top', $self->{_groupobjectclass}, 'extensibleObject'],
			'cn'          => $cn,
			'description' => $description
		);
	}
	else {
		$entry->add(
			'objectClass' => [ 'top', $self->{_groupobjectclass} ],
			'cn'          => $cn
		);
	}

	my $result = $self->ldapUpdate($entry);

	if ( $result->code ) {
		if ( ldap_error_name( $result->code ) eq "LDAP_ALREADY_EXISTS" ) {
			$log->info( "group " . $dn . " already exists" );
		}
		else {
			$log->error(
				    "CMU::LDAP::389::createGroup returned with error name: "
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
		$log->info( "Created 389 group " . $dn );
	}

	return $result;
}


sub renameGroup {
	my ( $self, $olddn, $groupName ) = @_;
	$log->debug("Calling CMU::LDAP::389::renameGroup(self, $olddn, $groupName)");

	my $newrdn = "cn=" . $groupName;
	my $result;
	my @attrs = ( $self->{_dnattribute} );
	my $entry =
	  $self->getLdapEntry( "(objectClass=" . $self->{_groupobjectclass} . ")",
		\@attrs, $olddn );
	$log->debug("in renameGroup. Right after getLdapEntry");
	if ( defined $entry ) {
		$log->debug("in renameGroup after defined entry. The entry is: " .  $entry->attributes . " " . $entry->changetype . " " . $entry->dn);
		$entry->changetype( 'moddn' );
		$log->debug("in renameGroup after defined entry added changetype. The entry is: " .  $entry->attributes . " " . $entry->changetype . " " . $entry->dn);
		$entry->add ( 'newrdn' => "$newrdn" );
		$log->debug("in renameGroup after defined entry added newrdn. The entry is: " .  $entry->attributes . " " . $entry->changetype . " " . $entry->dn);
		$entry->add ( 'deleteoldrdn' => '1' );
		$log->debug("in renameGroup after defined entry added deleteoldrdn. The entry is: " .  $entry->attributes . " " . $entry->changetype . " " . $entry->dn);

		$result = $self->ldapUpdate($entry);

		$log->debug("after ldapUpdate");
		if ( $result->code ) {
				$log->error(
					    "CMU::LDAP::389::renameGroup returned with error name: "
					  . ldap_error_name( $result->code )
					  . ", error description: "
					  . ldap_error_desc( $result->code )
					  . ", changetype: "
					  . $entry->changetype()
					  . ", ldif: "
					  . $entry->ldif() );
				die();
		}
		else {
			$log->info( "Renamed 389 group " . $olddn . " with " . $newrdn);
		}
	
	}
	else {
		$log->info("Skipping renameGroup as ldapentry " . $olddn . " not found ");
	}
	

	return $result;
}



sub getGroupDn {
	my ( $self, $groupname ) = @_;
	$log->debug("Calling CMU::LDAP::389::getGroupDn(self, $groupname)");

	$groupname =  $self->{_groupprefix} . escape_dn_value($groupname);

	my $dn = join( ",", $groupname, $self->{_syncou} );

	$log->debug( "groupname " . $groupname . " converted to DN " . $dn );
	return $dn;
}

sub getMemberDnForUnresolvable {
	my ( $self, $uid ) = @_;
	$log->debug("Calling CMU::LDAP::389::getMemberDnForUnresolvable(self, $uid)");

	my $dn =  $self->{_memberprefix} . $uid . ",ou=people," . $self->{_peoplebase};

	$log->debug( "uid " . $uid . " converted to DN " . $dn );
	return $dn;
}


sub constructMemberDnFromUid {
	my ( $self, $uid ) = @_;
	$log->debug("Calling CMU::LDAP::389::constructMemberDnFromUid(self, $uid)");

	my $memberdn = join( "=", "uid", $uid . ",ou=people,dc=berkeley,dc=edu");

	$log->debug( "uid " . $uid . " converted to DN " . $memberdn );
	return $memberdn;
}

sub addIsMemberOf {
	my ( $self, $memberdn, $groupdn ) = @_;
	$log->debug(
		"Calling CMU::LDAP::389::addIsMemberOf( self, $memberdn, $groupdn)");

	my $result;
	my @attrs = ("dn");
	my $entry =
	  $self->getLdapEntry(
		"!(berkeleyEduIsMemberOf=" . escape_filter_value($groupdn) . ")",
		\@attrs, $memberdn );

	if ( defined $entry ) {
		$entry->add( 'berkeleyEduIsMemberOf' => [$groupdn] );
		$log->debug("LDAP entry attributes:");
		$log->debug($entry->attributes);
		$log->debug($entry->dn);
		$log->debug($entry->ldif);
		

		$result = $self->ldapUpdate($entry);

		if ( $result->code ) {
			if ( ldap_error_name( $result->code ) eq
				"LDAP_TYPE_OR_VALUE_EXISTS" )
			{
				$log->info( " berkeleyEduIsMemberOf " . $groupdn
					  . " for uid "
					  . $memberdn
					  . " already exists" );
			}
			else {

				$log->error(
					"CMU::LDAP::389::addIsMemberOf returned with error name: "
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
				"Added berkeleyEduIsMemberOf " . $groupdn . " for uid " . $memberdn );
		}
	}
	else {
		$log->info(
			    "Skipping addIsMemberOf as ldapentry not found with groupdn "
			  . $groupdn
			  . "  not in userdn "
			  . $memberdn );
	}
	return $result;
}

sub removeIsMemberOf {
	my ( $self, $memberdn, $groupdn ) = @_;
	$log->debug(
		"Calling CMU::LDAP::389::removeIsMemberOf( self, $memberdn, $groupdn)"
	);

	my $result;
	my @attrs = ("dn");
	my $entry =
	  $self->getLdapEntry( "(berkeleyEduIsMemberOf=" . escape_filter_value($groupdn) . ")",
		\@attrs, $memberdn );

	if ( defined $entry ) {
		$entry->delete( 'berkeleyEduIsMemberOf' => [$groupdn] );

		my $result = $self->ldapUpdate($entry);

		if ( $result->code ) {
			$log->error(
				    "CMU::LDAP::389 removeIsMemberOf returned with error name: "
				  . ldap_error_name( $result->code )
				  . ", error description: "
				  . ldap_error_desc( $result->code )
				  . ", changetype: "
				  . $entry->changetype()
				  . ", ldif: "
				  . $entry->ldif() );
			die();
		}
		else {
			$log->info(
				"Removed berkeleyEduIsMemberOf " . $groupdn . " for uid " . $memberdn );
		}
	}
	else {
		$log->info(
			    "Skipping removeIsMemberOf as ldapentry not found with groupdn "
			  . $groupdn
			  . "  in userdn "
			  . $memberdn );
	}

	return $result;
}

sub getUidByIsMemberOf {
	my ( $self, $groupdn ) = @_;
	$log->debug("Calling CMU::LDAP::389::getUidByIsMemberOf( self, $groupdn)");

	my $result;
	my @members      = ();
	my @attrs        = ("uid");
	my $memberscount = 0;

	eval {
		$result = $self->ldapSearch(
			"&(berkeleyEduIsMemberOf="
			  . escape_filter_value($groupdn)
			  . ")(objectClass=person)",
			\@attrs, $self->{_peoplebase}
		);

		foreach my $entry ( $result->entries ) {
			push( @members, $entry->get_value("uid") );
		}
		$memberscount = @members;
	};

	if ($@) {
		die();
	}

	$log->debug(
		"Found " . $memberscount . " berkeleyEduIsMemberOf for group " . $groupdn );
	return @members;
}

sub DESTROY {
	my ($self) = @_;
	$log->debug("Calling CMU::LDAP::389::DESTROY(self)");
}

1;
