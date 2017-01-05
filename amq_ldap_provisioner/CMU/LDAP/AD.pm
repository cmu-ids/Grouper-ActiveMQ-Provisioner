#Copyright 2014 Carnegie Mellon University
#All rights reserved.

#Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

#1. Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.

#2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.

#3. Neither the name of the copyright holder nor the names of its contributors may be used to endorse or promote products derived from this software without specific prior written permission.

#THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

package CMU::LDAP::AD;

use Log::Log4perl;
use Net::DNS::Resolver;
use Net::LDAP::Entry;
use base ("CMU::LDAP");
use Data::Dumper;
use Net::LDAP::Util qw(escape_filter_value escape_dn_value);

use strict;
use warnings;

require CMU::CFG;
require CMU::Cache;
require CMU::Stats;

my $_dnssrv;
my $_ad = undef;
my $_samaccountname;
my $_cache;

my $log = Log::Log4perl->get_logger();

sub getInstance {
	$log->debug("Calling CMU::LDAP::AD::getInstance(self)");
	if ( !defined $_ad ) {
		my $class = shift;
		my $self  = {};
		$_ad = bless $self, $class;

		CMU::CFG::readConfig('configuration.pl');

		$_ad->{_dnssrv}            = $CMU::CFG::_CFG{'AD'}{'server'};
		$_ad->{_binddn}            = $CMU::CFG::_CFG{'AD'}{'binddn'};
		$_ad->{_password}          = $CMU::CFG::_CFG{'AD'}{'password'};
		$_ad->{_port}              = $CMU::CFG::_CFG{'AD'}{'port'};
		$_ad->{_syncou}            = $CMU::CFG::_CFG{'AD'}{'syncou'};
		$_ad->{_peoplebase}        = $CMU::CFG::_CFG{'AD'}{'peoplebase'};
		$_ad->{_groupobjectclass}  = $CMU::CFG::_CFG{'AD'}{'groupobjectclass'};
		$_ad->{_personobjectclass} = $CMU::CFG::_CFG{'AD'}{'personobjectclass'};
		$_ad->{_memberattribute}   = $CMU::CFG::_CFG{'AD'}{'memberattribute'};
		$_ad->{_dnattribute}       = $CMU::CFG::_CFG{'AD'}{'dnattribute'};
		$_ad->{_memberprefix}      = $CMU::CFG::_CFG{'AD'}{'memberprefix'};
		$_ad->{_groupprefix}      = $CMU::CFG::_CFG{'AD'}{'groupprefix'};
		$_ad->{_env}               = $CMU::CFG::_CFG{'ldap'}{'env'};
		$_ad->{_logtoerrorqueue}   = $CMU::CFG::_CFG{'ldap'}{'logtoerrorqueue'};
#		$_ad->{_server}            = $_ad->getPdc();
		$_ad->{_server}		   = $CMU::CFG::_CFG{'AD'}{'server'};		
		$_ad->{_cache}             = CMU::Cache->new;
		$_ad->connect();

	}

	return $_ad;
}

sub getPdc {
	my ($self) = @_;
	$log->debug("Calling CMU::LDAP::AD::getPdc()");

	my $result = Net::DNS::Resolver->new;

	$log->debug("The resolver state after new: " . $result->print);
	#my $query = $result->send( $self->{_dnssrv}, "SRV" );
	my $query = $result->send( $self->{_dnssrv});
	$log->debug("The resolver state after send: " . $result->print);
	$log->debug("The resolver state after send as a string: " . $result->string);
	
	$log->debug("The query answer: " . $query->answer);
	
	if ($query) {
		foreach my $rr ( $query->answer ) {
			$log->debug("The query answer inside foreach: " . $query->answer);
			$log->debug("The rr type: " . $rr->type);
			next unless $rr->type eq 'A';
			$log->debug("The rr target: " . $rr->target);
			return $rr->target;
		}
		$log->error("SRV lookup failed:");
		die();
	}
	else {
		$log->error( "SRV lookup failed: " . $result->errorstring );
		die();
	}
}

sub getSAMAccountNameFromLdapEntry {
	my ( $self, $entry ) = @_;
	$log->debug(
		"Calling CMU::LDAP::AD::getSAMAccountNameFromLdapEntry( self, ldapentry)");
		
	my $samaccountname = $entry->get_value("sAMAccountName");
	$samaccountname =~ s/[\"\[\]:;|=+*?<>\/\\,]/-/g;
	return $entry->get_value("sAMAccountName");
}

sub getSAMAccountNameFromGroupName {
	my ( $self, $groupname ) = @_;
	$log->debug(
		"Calling CMU::LDAP::AD::getSAMAccountNameFromGroupName( self, $groupname)");

#	my $samaccountname = join( ".", reverse split( ":", $groupname ) );
	my $samaccountname = (split ":", $groupname )[-1];	
	$samaccountname =~ s/[\"\[\]:;|=+*?<>\/\\, ]/-/g;
	return substr($samaccountname, 0, 256);
}

sub updateSAMAccountName {
	my ( $self, $dn, $samaccountname ) = @_;
	$log->debug(
		"Calling CMU::LDAP::AD::updateSAMAccountName(self, $dn, $samaccountname)");

	my $result;
	my @attrs = ( $self->{_dnattribute} );
	my $entry =
	  $self->getLdapEntry( "(objectClass=" . $self->{_groupobjectclass} . ")",
		\@attrs, $dn );
	if ( defined $entry ) {
		$entry->replace( 'sAMAccountName' => $samaccountname );

		my $result = $self->ldapUpdate($entry);

		if ( $result->code ) {
			if ( ldap_error_name( $result->code ) eq
				"LDAP_TYPE_OR_VALUE_EXISTS" )
			{
				$log->info(
					$samaccountname . " already exists for group " . $dn );
			}
			else {
				$log->error(
					"CMU::LDAP::updateSAMAccountName returned with error name: "
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
			$log->info( "Updated sAMAccountName with "
				  . $samaccountname
				  . " for group "
				  . $dn );
		}
	}
	else {
		$log->info(
			"Skipping updateSAMAccountName as ldapentry not found for group "
			  . $dn );
	}

	return $result;
}

sub createGroup {
	my ( $self, $dn, $description ) = @_;

	$log->debug("Calling CMU::LDAP::AD::createGroup(self, $dn, $description)");

	my @dn_parts     = split( ',', $dn );
	my @syncou_parts = split( ',', $self->{_syncou} );

	my $result;
	my @oudn = ();
	for my $i ( 1 .. $#dn_parts - $#syncou_parts - 1 ) {
		shift(@dn_parts);
		my $ou = join( ",", @dn_parts );
		push( @oudn, $ou );
	}

	@oudn = reverse(@oudn);

	foreach (@oudn) {
		if ( !$self->checkOUExists($_) ) {
			$result = $self->createOU($_);
		}
	}

	my $samaccountname =
	  $self->getSAMAccountNameFromGroupName( $self->{_amqmesg}->{"name"} );
	my $entry = Net::LDAP::Entry->new($dn);

	if ( $description ne '' ) {
		$entry->add(
			'objectclass'    => [ 'top', 'group' ],
			'sAmAccountName' => $samaccountname,
			'description'    => $description
		);
	}
	else {
		$entry->add(
			'objectclass'    => [ 'top', 'group' ],
			'sAmAccountName' => $samaccountname
		);
	}

	$result = $self->ldapUpdate($entry);

	if ( $result->code ) {
		if ( ldap_error_name( $result->code ) eq "LDAP_ALREADY_EXISTS" ) {
			$log->info( "group " . $dn . " already exists in AD" );
		}
		else {

			$log->error( "CMU::LDAP::AD::createGroup returned with error name: "
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
		$log->info("Created AD group $dn");
	}

	return $result;
}

sub renameGroup {
        my ( $self, $olddn, $groupName ) = @_;
        $log->debug("Calling CMU::LDAP::AD::renameGroup(self, $olddn, $groupName)");

	# Get the new rdn of the group
        my $newrdn = $self->{_groupprefix} . $self->getSAMAccountNameFromGroupName( $groupName );
        my $newsuperior = $self->getNewSuperior( $groupName );
		
	# Make sure all the OUs as part of the DN exist
	my @dn_parts     = split( ',', $newsuperior );
	my @syncou_parts = split( ',', $self->{_syncou} );

	my $result;
	my @oudn = ();
	for my $i ( 1 .. $#dn_parts - $#syncou_parts ) {
		my $ou = join( ",", @dn_parts );
		push( @oudn, $ou );
		shift(@dn_parts);
	}

	@oudn = reverse(@oudn);

	foreach (@oudn) {
		if ( !$self->checkOUExists($_) ) {
			$result = $self->createOU($_);
		}
	}
		
	# Find the group in AD before change
        my @attrs = ( $self->{_dnattribute} );
        my $entry =
          $self->getLdapEntry( "(objectClass=" . $self->{_groupobjectclass} . ")",
                \@attrs, $olddn );

	# We found it so create the moddn request
        if ( defined $entry ) {
                $entry->changetype( 'moddn' );
                $entry->add ( 'newrdn' => $newrdn );
                $entry->add ( 'deleteoldrdn' => '1' );
                $entry->add ( 'newsuperior' => $newsuperior );
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
                        $log->info( "Renamed AD group " . $olddn . " with " . $newrdn);
                }

        }
        else {
                $log->info("Skipping renameGroup as ldapentry " . $olddn . " not found ");
        }


        return $result;
}



sub getNewSuperior {
	my ( $self, $groupname ) = @_;
	$log->debug("Calling CMU::LDAP::AD::getSuperior(self, $groupname)");

	my @list  = split( ':', $groupname );
	pop @list;
	my $count = 0;

	foreach my $token (@list) {
		if ( $count != $#list ) {
			$token = join( "=", "OU", escape_dn_value($token) );
		}
		else {
			$token = join( "=", "OU", escape_dn_value($token) );
		}
		$count++;
	}

	my $dn = join( ",", reverse(@list), $self->{_syncou} );

	$log->debug( "from groupname " . $groupname . " the new superior is " . $dn );

	return $dn;
}



sub getGroupMembers {
	my ( $self, $groupdn ) = @_;
	$log->debug("Calling CMU::LDAP::AD::getMembers( self, $groupdn)");

	my @attrs = ("member;range=0-*");
	my $result;
	my @members = ();
	my @tmp     = ();
	my $first   = 0;
	my $size    = 1500;
	my $last    = $first + $size - 1;
	my $done    = 0;

	while ( !$done ) {
		eval {
			$log->debug(
				"Performing ldap search with members range " . $first . " to "
				  . $last . " for "
				  . $groupdn );
			$result = $self->ldapSearch(
				"&(distinguishedName="
				  . escape_filter_value($groupdn)
				  . ")(objectClass="
				  . $self->{_groupobjectclass} . ")",
				\@attrs, $self->{_syncou}
			);

			my $entry = $result->pop_entry();
			@tmp = $entry->get_value("member;range=$first-*");
			if ( @tmp == 0 ) {

				@tmp =
				  $entry->get_value( "member;range=" . $first . "-" . $last );
				push @members, @tmp;

				$first += $size;
				$last = $first + $size - 1;

				@attrs = ( "member;range=" . $first . "-*" );

				if ( @tmp == 0 ) {
					$done = 1;
				}
			}
			else {
				push @members, @tmp;
				$done = 1;
			}
		};
		if ($@) {
			die();
		}
	}

	$log->debug(
		"Found " . scalar @members . " members for group " . $groupdn );
	return @members;
}

sub disconnect {
	my ($self) = @_;

	$log->debug("Calling CMU::LDAP::AD::disconnect(self)");

	if ( defined $self->{_ldap} ) {
		eval { $self->{_ldap}->unbind; };

		if ($@) {
			$log->error("Could not unbind LDAP because:$!");
		}
		undef $self->{_ldap};
	}

	undef $_ad;
}

sub getGroupDn {
	my ( $self, $groupname ) = @_;
	$log->debug("Calling CMU::LDAP::AD::getGroupDn(self, $groupname)");

	my @list  = split( ':', $groupname );
	my $count = 0;

	foreach my $token (@list) {
		if ( $count != $#list ) {
			$token = join( "=", "OU", escape_dn_value($token) );
		}
		else {
			my $samaccountname =  substr($self->getSAMAccountNameFromGroupName($groupname), 0, 64);
			$token =  $self->{_groupprefix} . escape_dn_value($samaccountname);
		}
		$count++;
	}

	my $dn = join( ",", reverse(@list), $self->{_syncou} );

	$log->debug( "groupname " . $groupname . " converted to DN " . $dn );
	return $dn;
}

sub DESTROY {
	my ($self) = @_;
	$log->debug("Calling CMU::LDAP::AD::DESTROY(self)");
}

1;
