#Copyright 2014 Carnegie Mellon University
#All rights reserved.

#Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

#1. Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.

#2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.

#3. Neither the name of the copyright holder nor the names of its contributors may be used to endorse or promote products derived from this software without specific prior written permission.

#THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

package CMU::ActiveMQ;
use Net::Stomp;
use JSON;
use Data::Dumper;
use strict;
use warnings;

require CMU::CFG;
require CMU::Stats;

my $_stomp;
my $_primary;
my $_secondary;
my $_port;
my $_login;
my $_password;
my $_ldapqueue;
my $_errorqueue;
my $_env;
my $_activemq = undef;
my $_frame;
my $_nextframe;
my @_removemember;
my @_addmember;
my @_unackframes;
my $_groupname;

my $log = Log::Log4perl->get_logger();

sub new {
	$log->debug("Calling CMU::ActiveMQ::new()");
	my $class = shift;
	my $self  = {};
	$_activemq = bless $self, $class;

	CMU::CFG::readConfig('configuration.pl');
	$_activemq->{_primary}    = $CMU::CFG::_CFG{'activemq'}{'primary'};
	$_activemq->{_secondary}  = $CMU::CFG::_CFG{'activemq'}{'secondary'};
	$_activemq->{_port}       = $CMU::CFG::_CFG{'activemq'}{'port'};
	$_activemq->{_login}      = $CMU::CFG::_CFG{'activemq'}{'login'};
	$_activemq->{_password}   = $CMU::CFG::_CFG{'activemq'}{'password'};
	$_activemq->{_ldapqueue}  = $CMU::CFG::_CFG{'activemq'}{'ldapqueue'};
	$_activemq->{_errorqueue} = $CMU::CFG::_CFG{'activemq'}{'errorqueue'};
	$_activemq->{_env}        = $CMU::CFG::_CFG{'ldap'}{'env'};
	$_activemq->connect();
	$_activemq->subscribe();

	return $_activemq;
}

sub getStomp {
	my ($self) = @_;

	$log->debug("Calling CMU::ActiveMQ::getStomp(self)");

	return $self->{_stomp};
}

sub sendToErrorQueue {
	my ( $self, $mesg ) = @_;

	$log->debug("Calling CMU::ActiveMQ::isConnected(self, $mesg)");
	eval {
		$self->{_stomp}->send(
			{
				destination => $self->{_errorqueue},
				body        => $mesg,
				persistent  => 'true'
			}
		);

	};
	if ($@) {
		$log->error( "Could not send message " . $mesg . " due to error :$!" );
		die();
	}
}

sub disconnect {
	my ($self) = @_;

	$log->debug("Calling CMU::ActiveMQ::disconnect(self)");

	if ( defined $self->{_stomp} ) {
		eval { $self->{_stomp}->disconnect(); };
		if ($@) {
			$log->error("Could not disconnect stomp connection because:$!");
		}
		undef $self->{_stomp};
		undef $_activemq;
	}
}

sub connect {
	my ($self) = @_;
	$log->debug("Calling CMU::ActiveMQ::connect()");

	eval {
		$self->{_stomp} = Net::Stomp->new(
			{
				hosts => [
					{
						hostname    => $self->{_primary},
						port        => $self->{_port},
						ssl         => 0,
						ssl_options => { SSL_verify_mode => 0 }
					},
					{
						hostname    => $self->{_secondary},
						port        => $self->{_port},
						ssl         => 1,
						ssl_options => { SSL_verify_mode => 0 }
					}
				]
			}
		);
	};

	if ($@) {
		$log->error("Could not create stomp instance because:$!");
		return;
	}

	$log->debug(
		"Connecting to stomp using login:$self->{_login} passcode:'xxxxxx'");

	eval {
		my $conn =
		  $self->{_stomp}->connect(
			{ login => $self->{_login}, passcode => $self->{_password} } );
	};

	if ($@) {
		$log->error("Could not create stomp connection because:$!");
		return;
	}

	$log->info("Connected to stomp server");

	return $self->{_stomp};
}

sub subscribe {
	my ($self) = @_;
	$log->debug("Calling CMU::ActiveMQ::subscribe(self)");

	eval {
		$self->{_stomp}
		  ->subscribe( { destination => $self->{_ldapqueue}, ack => 'client' },
			'activemq.prefetchSize' => 1 );
	};
	if ($@) {
		$log->error( "Couldn't subscribe to queue " . $self->{_ldapqueue} );
		die();
	}
}

sub getUnAckedFrames {
	my ($self) = @_;
	$log->debug("Calling CMU::ActiveMQ::getUnAckedFrames(self)");

	if ( defined $self->{_unackframes} ) {
		return @{ $self->{_unackframes} };
	}
	else {
		return ();
	}
}

sub processMessageChangeLogBatch {
	my ( $self, $ldap ) = @_;
	$log->debug(
		"Calling CMU::ActiveMQ::processMessageChangeLogBatch(self, ldap)");

	eval {
		my $groupdn;
		my @attrs           = ();
		my @groupermembers  = ();
		my @ldapmembers     = ();
		my @add_memberdn    = ();
		my @remove_memberdn = ();

		if ( defined $self->{_addmember} || defined $self->{_removemember} ) {
			$groupdn = $ldap->getGroupDn( $self->{_groupname} );
			my $entry =
			  $ldap->getLdapEntry(
				"(objectClass=" . $ldap->{_groupobjectclass} . ")",
				\@attrs, $groupdn );

			if ( defined $entry ) {
				if ( $CMU::CFG::_CFG{'ldap'}{'env'} eq "AD" ) {
					@ldapmembers = $ldap->getGroupMembers($groupdn);

					my $samaccountnameLdap =
					  $ldap->getSAMAccountNameFromLdapEntry($entry);
					my $samaccountnameGrouper =
					  $ldap->getSAMAccountNameFromGroupName(
						$self->{_groupname} );

					if ( $samaccountnameGrouper ne $samaccountnameLdap ) {
						$ldap->updateSAMAccountName( $groupdn,
							$samaccountnameGrouper );
					}
				}
				else {
					@ldapmembers = $ldap->getGroupMembers($entry);
				}

				my %add_memberdn_seen;
				foreach ( @{ $self->{_addmember} } ) {
					my $memberdn = $ldap->getMemberDn($_);
					if ( defined $memberdn ) {
						next if $add_memberdn_seen{$memberdn}++;
						push( @add_memberdn, $memberdn );
					}
					else {
						$log->info( "Skipping add member to " . $groupdn
							  . " as member "
							  . $_
							  . " doesn't exist " );
					}
				}

				my %remove_memberdn_seen;
				foreach ( @{ $self->{_removemember} } ) {
					my $memberdn = $ldap->getMemberDn($_);
					if ( defined $memberdn ) {
						next if $remove_memberdn_seen{$memberdn}++;
						push( @remove_memberdn, $memberdn );
					}
					else {
						if ( $CMU::CFG::_CFG{'ldap'}{'env'} eq "389" ) {
							if ( $_ =~ /:/ ) {
								push( @remove_memberdn, $ldap->getGroupDn($_) );
							}
							else {
								push( @remove_memberdn,
									$ldap->getMemberDnForUnresolvable($_) );
							}
						}
						else {
							$log->info(
								    "Skipping remove member from " . $groupdn
								  . " as uid "
								  . $_
								  . " doesn't exist" );
						}
					}
				}

				$_ = lc for @add_memberdn;
				$_ = lc for @ldapmembers;
				$_ = lc for @remove_memberdn;
			
				my @add_members =
				  CMU::Util::arrayMinus( \@add_memberdn, \@ldapmembers );

				my @remove_members =
				  CMU::Util::arrayMinus( \@remove_memberdn, \@ldapmembers );

				if (@add_members) {
					$ldap->bulkGroupMemberAdd( \@add_members, $groupdn );
				}

				if (@remove_members) {

					#finding members to remove that exist in group
					my @remove =
					  CMU::Util::arrayMinus( \@remove_memberdn,
						\@remove_members );
					if (@remove) {
						$ldap->bulkGroupMemberRemove( \@remove, $groupdn );
					}
				}
				else {
					if (@remove_memberdn) {
						$ldap->bulkGroupMemberRemove( \@remove_memberdn,
							$groupdn );
					}
				}
			}
		}
	};
	if ($@) {
		die();
	}
}

sub resetChangeLogBatch {
	my ($self) = @_;
	$log->debug("Calling CMU::ActiveMQ::resetChangeLogBatch(self)");
	undef $self->{_frame};
	undef $self->{_nextframe};
	undef $self->{_removemember};
	undef $self->{_addmember};
	undef $self->{_unackframes};
	undef $self->{_groupname};
}

sub addMessageChangeLogToBatch {
	my ( $self, $ldap, $frame, $nextframe ) = @_;
	$log->debug(
"Calling CMU::ActiveMQ::addChangelogMessageToBatch(self, ldap, frame, nextframe)"
	);

	my $done = 0;
	my $nextmesg;
	my $nextdata;
	my $mesg;
	my $data;

	eval {
		$mesg           = $frame->body;
		$data           = JSON::decode_json($mesg);
		$self->{_frame} = $frame;

		if ( defined $nextframe ) {

			$self->{_nextframe} = $nextframe;
			$nextmesg           = $nextframe->body;
			$nextdata           = JSON::decode_json($nextmesg);

			if (   $data->{"name"} ne $nextdata->{"name"}
				|| $data->{"operation"} ne $nextdata->{"operation"} )
			{
				$done = 1;
			}
		}
		else {
			$done = 1;
		}

		$self->{_groupname} = $data->{"name"};
		if ( $data->{"operation"} eq "addMember" ) {
			push( @{ $self->{_addmember} },   $data->{"memberId"} );
			push( @{ $self->{_unackframes} }, $frame );
		}
		else {
			push( @{ $self->{_removemember} }, $data->{"memberId"} );
			push( @{ $self->{_unackframes} },  $frame );
		}
	};
	if ($@) {
		die();
	}
	return $done;
}

sub processMessageChangeLog {
	my @groupermembers = ();
	my ( $self, $ldap, $data ) = @_;
	$log->debug(
		"Calling CMU::ActiveMQ::processMessageChangeLog(self, ldap, data)");

	eval {
		if ( defined $data->{"memberList"} )
		{
			@groupermembers = @{ $data->{"memberList"} };
		}

		my $groupdn = $ldap->getGroupDn( $data->{"name"} );

		if ( $data->{"operation"} eq "createGroup" ) {
			my @attrs = ("dn");
			my $entry =
			  $ldap->getLdapEntry(
				"(objectClass=" . $ldap->{_groupobjectclass} . ")",
				\@attrs, $groupdn );

			if ( !defined $entry ) {
				$ldap->createGroup($groupdn);
			}
			else {
				$log->info( "Skipping create group as group  " . $groupdn
					  . " already exists" );
			}
		}
		elsif ( $data->{"operation"} eq "addMember" ) {
			my $memberdn = $ldap->getMemberDn( $data->{"memberId"} );
			if ( defined $memberdn ) {
				$ldap->addGroupMember( $memberdn, $groupdn );
			}
			else {
				$log->info( "Skipping add member to " . $groupdn
					  . " as member "
					  . $data->{'memberId'}
					  . " doesn't exist " );
			}
		}
		elsif ( $data->{"operation"} eq "addIsMemberOf" ) {
			my $memberdn = $ldap->getMemberDn( $data->{"memberId"} );
			if ( defined $memberdn ) {
				$ldap->addIsMemberOf( $memberdn, $groupdn );
			}
			else {
				$log->info( "Skipping add isMemberOf to uid  "
					  . $data->{'memberId'}
					  . " as uid doesn't exist" );
			}
		}
		elsif ( $data->{"operation"} eq "removeMember" ) {
			my $memberdn = $ldap->getMemberDn( $data->{"memberId"} );
			if ( defined $memberdn ) {
				$ldap->removeGroupMember( $memberdn, $groupdn );
			}
			else {
				if ( $self->{_env} eq "389" ) {
					$memberdn =
					  $ldap->constructMemberDnFromUid( $data->{"memberId"} );
					$ldap->removeGroupMember( $memberdn, $groupdn );
				}
				else {
					$log->info( "Skipping remove member from " . $groupdn
						  . " as uid "
						  . $data->{'memberId'}
						  . " doesn't exist" );
				}
			}
		}
		elsif ( $data->{"operation"} eq "removeIsMemberOf" ) {
			my $memberdn = $ldap->getMemberDn( $data->{"memberId"} );
			if ( defined $memberdn ) {
				{
					$ldap->removeIsMemberOf( $memberdn, $groupdn );
				}
			}
			else {
				$log->info( "Skipping remove isMemberOf from uid  "
					  . $data->{'memberId'}
					  . " as uid doesn't exist" );
			}
		}
		elsif ( $data->{"operation"} eq "updateGroup" ) {
			if (   $data->{"description"} ne ''
				&& $data->{"olddescription"} eq '' )
			{
				$ldap->addGroupDescription( $groupdn, $data->{"description"} );
			}
			elsif ($data->{"description"} ne ''
				&& $data->{"olddescription"} ne '' )
			{
				$ldap->replaceGroupDescription( $groupdn,
					$data->{"description"} );
			}
			elsif ($data->{"description"} eq ''
				&& $data->{"olddescription"} ne '' )
			{
				$ldap->removeGroupDescription($groupdn);
			}
			else {
				$log->info( "Skipping update group for " . $groupdn
					  . " as both old and new value for description is empty "
				);
			}
		}
		elsif ( $data->{"operation"} eq "deleteGroup" ) {
			$ldap->deleteObject($groupdn);
		}
		elsif ( $data->{"operation"} eq "deleteGroupIsMemberOf" ) {
			my $groupdn = $ldap->getGroupDn( $data->{"name"} );

			my @ldapmembers = $ldap->getUidByIsMemberOf($groupdn);

			foreach (@ldapmembers) {
				my $memberdn = $ldap->getMemberDn($_);
				if ( defined $memberdn ) {
					$ldap->removeIsMemberOf( $memberdn, $groupdn );
				}
			}
		}
		elsif ( $data->{"operation"} eq "addPrivilege" ) {
			my $memberdn = $ldap->getMemberDn( $data->{"memberId"} );
			if ( defined $memberdn ) {
				$ldap->addGroupOwner( $memberdn, $groupdn );
			}
			else {
				$log->info( "Skipping add owner to " . $groupdn
					  . " as member "
					  . $data->{'memberId'}
					  . " doesn't exist " );
			}
		}
		elsif ( $data->{"operation"} eq "removePrivilege" ) {
			my $memberdn = $ldap->getMemberDn( $data->{"memberId"} );
			if ( defined $memberdn ) {
				$ldap->removeGroupOwner( $memberdn, $groupdn );
			}
			else {
				if ( $self->{_env} eq "389" ) {
					$memberdn =
					  $ldap->constructMemberDnFromUid( $data->{"memberId"} );
					$ldap->removeGroupOwner( $memberdn, $groupdn );
				}
				else {
					$log->info( "Skipping remove owner from " . $groupdn
						  . " as uid "
						  . $data->{'memberId'}
						  . " doesn't exist" );
				}
			}
		}
		elsif ( $data->{"operation"} eq "renameGroup" ) {
			if (   $data->{"name"} ne ''
				&& $data->{"oldname"} ne '' )
			{
				my $olddn = $ldap->getGroupDn( $data->{"oldname"} );
				$ldap->renameGroup($olddn, $data->{"name"} );
			}
			else {
				$log->info( "Skipping rename group for new name " . $data->{"name"}
					  . " and old name " . $data->{"oldname"}
					  . " as old or new value for group name is empty "
				);
			}
		}
		elsif ( $data->{"operation"} eq "renameGroupIsMemberOf" ) {
			if (   $data->{"name"} ne ''
				&& $data->{"oldname"} ne '' )
			{
				my $olddn = $ldap->getGroupDn( $data->{"oldname"} );
				my $newdn = $ldap->getGroupDn( $data->{"name"} );
				
				my @ldapmembers = $ldap->getUidByIsMemberOf($olddn);

				foreach (@ldapmembers) {
					my $memberdn = $ldap->getMemberDn($_);
					if ( defined $memberdn ) {
						$ldap->removeIsMemberOf( $memberdn, $olddn );
						$ldap->addIsMemberOf( $memberdn, $newdn );
					}
				}				
			}
			else {
				$log->info( "Skipping rename group isMemberOf for new name " . $data->{"name"}
					  . " and old name " . $data->{"oldname"}
					  . " as old or new value for group name is empty "
				);
			}			
		}
	};
	if ($@) {
		die();
	}
}

sub processMessageFullSyncIsMemberOf {
	my @groupermembers            = ();
	my @ldapmembers               = ();
	my @add_ismemberof_members    = ();
	my @remove_ismemberof_members = ();

	my ( $self, $ldap, $data ) = @_;
	$log->debug(
"Calling CMU::ActiveMQ::processMessageFullSyncIsMemberOf(self, ldap, data)"
	);

	eval {
		my $ldaptarget = $ldap->getLdapTargetName();
		if ( defined $data->{"memberList"} ) {
			@groupermembers = @{ $data->{"memberList"} };
		}

		my $groupdn = $ldap->getGroupDn( $data->{"name"} );
		@ldapmembers            = $ldap->getUidByIsMemberOf($groupdn);
		
		$_ = lc for @groupermembers;
		$_ = lc for @ldapmembers;
			
		@add_ismemberof_members =
		  CMU::Util::arrayMinus( \@groupermembers, \@ldapmembers );

		foreach (@add_ismemberof_members) {
			my $memberdn = $ldap->getMemberDn($_);
			if ( defined $memberdn ) {
				$ldap->addIsMemberOf( $memberdn, $groupdn );
				$log->error( "FullSyncIsMemberOf adding isMemberOf " . $groupdn
					  . " to member "
					  . $memberdn );

			}
		}

		@remove_ismemberof_members =
		  CMU::Util::arrayMinus( \@ldapmembers, \@groupermembers );

		foreach (@remove_ismemberof_members) {
			my $memberdn = $ldap->getMemberDn($_);
			if ( defined $memberdn ) {
				$ldap->removeIsMemberOf( $memberdn, $groupdn );
				$log->error(
					    "FullSyncIsMemberOf removing isMemberOf " . $groupdn
					  . " from member "
					  . $memberdn );
			}
		}

		$log->info( "Grouper members count: "
			  . scalar @groupermembers . " for "
			  . $data->{'name'} );
		$log->info( "LDAP member count: "
			  . scalar @ldapmembers
			  . " by isMemberOf for "
			  . $groupdn );
		$log->info( "Add isMemberOf count: "
			  . scalar @add_ismemberof_members . " for "
			  . $data->{'name'} );
		$log->info( "Remove isMemberOf count: "
			  . scalar @remove_ismemberof_members . " for "
			  . $data->{'name'} );
		$log->info( "FullsyncIsMemberOf completed successfully for "
			  . $data->{'name'} );

	};
	if ($@) {
		die();
	}
}

sub processMessageFullSyncPrivilege {
	my @grouperowners   = ();
	my @ldapuidmembers  = ();
	my @ldapowners      = ();
	my @add_owners      = ();
	my @remove_owners   = ();
	my @add_ownerdn     = ();
	my @remove_ownerdn  = ();
	my $addcount        = 0;
	my $removecount     = 0;
	my $notfoundadd     = 0;
	my $notfoundremove  = 0;
	my %hashldapmembers = ();

	my ( $self, $ldap, $data ) = @_;
	$log->debug(
"Calling CMU::ActiveMQ::processMessageFullSyncPrivilege(self, ldap, data)"
	);

	eval {
		if ( defined $data->{"memberList"} )
		{
			@grouperowners = @{ $data->{"memberList"} };
		}

		my $groupdn = $ldap->getGroupDn( $data->{"name"} );
		my @attrs   = ();
		my $entry   =
		  $ldap->getLdapEntry(
			"(objectClass=" . $ldap->{_groupobjectclass} . ")",
			\@attrs, $groupdn );

		if ( defined $entry ) {
			@ldapowners = $ldap->getGroupOwners($entry);

			%hashldapmembers =
			  CMU::Util::covertMemberDNListToMembersUidHash(
				$ldap->getLdapTargetName(), @ldapowners );

			@ldapowners =
			  CMU::Util::covertMemberDNListToMembersUidList(
				$ldap->getLdapTargetName(), @ldapowners );
				
			$_ = lc for @grouperowners;
			$_ = lc for @ldapowners;

			@add_owners =
			  CMU::Util::arrayMinus( \@grouperowners, \@ldapowners );

			foreach (@add_owners) {
				my $memberdn = $ldap->getMemberDn($_);
				if ( defined $memberdn ) {
					$addcount++;
					push( @add_ownerdn, $memberdn );
				}
				else {
					$notfoundadd++;
				}
			}

			@remove_owners =
			  CMU::Util::arrayMinus( \@ldapowners, \@grouperowners );

			foreach (@remove_owners) {
				my $ownerdn = $hashldapmembers{$_};
				if ( defined $ownerdn ) {
					$removecount++;
					push( @remove_ownerdn, $ownerdn );
				}
			}

			if (@add_ownerdn) {
				$ldap->bulkGroupOwnerAdd( \@add_ownerdn, $groupdn );
			}

			if (@remove_ownerdn) {
				$ldap->bulkGroupOwnerRemove( \@remove_ownerdn, $groupdn );
			}
		}
		else {
			$log->info( "ldap group doesn't exist for grouper group "
				  . $data->{"name"} );
		}

		$log->info( "Grouper owners count: "
			  . scalar @grouperowners . " for "
			  . $data->{'name'} );
		$log->info(
			"LDAP owners count: " . scalar @ldapowners . " for " . $groupdn );
		$log->info(
			"Add owners count: " . $addcount . " for " . $data->{'name'} );
		$log->info( "Add owners not found count: "
			  . $notfoundadd . " for "
			  . $data->{'name'} );
		$log->info( "Remove owners count: "
			  . $removecount . " for "
			  . $data->{'name'} );
		$log->info(
			"FullsyncPrivilege completed successfully for " . $data->{'name'} );

	};
	if ($@) {
		die();
	}
}

sub processMessageFullSync {
	my @groupermembers   = ();
	my @groupermembersdn = ();
	my @ldapuidmembers   = ();
	my @ldapmembers      = ();
	my @add_members      = ();
	my @remove_members   = ();
	my $notfound         = 0;

	my ( $self, $ldap, $data ) = @_;
	$log->debug(
		"Calling CMU::ActiveMQ::processMessageFullSync(self, ldap, data)");

	eval {
		if ( defined $data->{"memberList"} )
		{
			@groupermembers = @{ $data->{"memberList"} };
		}

		my $groupdn = $ldap->getGroupDn( $data->{"name"} );
		my @attrs   = ();
		my $entry   =
		  $ldap->getLdapEntry(
			"(objectClass=" . $ldap->{_groupobjectclass} . ")",
			\@attrs, $groupdn );

		if ( defined $entry ) {
			if ( $CMU::CFG::_CFG{'ldap'}{'env'} eq "AD" ) {
				@ldapmembers = $ldap->getGroupMembers($groupdn);

				my $samaccountnameLdap =
				  $ldap->getSAMAccountNameFromLdapEntry($entry);
				my $samaccountnameGrouper =
				  $ldap->getSAMAccountNameFromGroupName( $data->{"name"} );

				if ( $samaccountnameGrouper ne $samaccountnameLdap ) {
					$ldap->updateSAMAccountName( $groupdn,
						$samaccountnameGrouper );
				}
			}
			else {
				@ldapmembers = $ldap->getGroupMembers($entry);
			}

			foreach (@groupermembers) {
				my $memberdn = $ldap->getMemberDn($_);
				if ( defined $memberdn ) {
					push( @groupermembersdn, $memberdn );
				}
				else {
					$notfound++;
				}
			}

			$_ = lc for @groupermembersdn;
			$_ = lc for @ldapmembers;
			
			@add_members =
			  CMU::Util::arrayMinus( \@groupermembersdn, \@ldapmembers );

			@remove_members =
			  CMU::Util::arrayMinus( \@ldapmembers, \@groupermembersdn );
			  
			if (@remove_members) {
				my @batch_remove_members = ();

				foreach (@remove_members) {
					push( @batch_remove_members, $_ );

					if (   @batch_remove_members
						&& $#batch_remove_members == 499 )
					{
						$ldap->bulkGroupMemberRemove( \@batch_remove_members,
							$groupdn );
							undef(@batch_remove_members);
					}

				}
				if (@batch_remove_members) {
					$ldap->bulkGroupMemberRemove( \@batch_remove_members,
						$groupdn );
				}
			}

			if (@add_members) {
				my @batch_add_members = ();
				foreach (@add_members) {

					push( @batch_add_members, $_ );

					if ( @batch_add_members && $#batch_add_members == 499 ) {
						$ldap->bulkGroupMemberAdd( \@batch_add_members,
							$groupdn );
							undef(@batch_add_members);
					}
				}

				if (@batch_add_members) {
					$ldap->bulkGroupMemberAdd( \@batch_add_members, $groupdn );
				}
			}
		}
		else {
			$ldap->createGroup( $groupdn, $data->{"description"} );

			foreach (@groupermembers) {
				my $memberdn = $ldap->getMemberDn($_);
				if ( defined $memberdn ) {
					push( @add_members, $memberdn );
				}
				else {
					$notfound++;
				}

				if ( @add_members && $#add_members == 499 ) {
					$ldap->bulkGroupMemberAdd( \@add_members, $groupdn );
					undef(@add_members);
				}
			}

			if (@add_members) {
				$ldap->bulkGroupMemberAdd( \@add_members, $groupdn );
			}
		}

		$log->info( "Grouper members count: "
			  . scalar @groupermembers . " for "
			  . $data->{'name'} );
		$log->info(
			"LDAP members count: " . scalar @ldapmembers . " for " . $groupdn );
		$log->info( "Add members count: "
			  . scalar @add_members . " for "
			  . $data->{'name'} );
		$log->info(
			"Grouper members not resolved in ldap count: " . $notfound );
		$log->info( "Fullsync completed successfully for " . $data->{'name'} );

	};
	if ($@) {
		die();
	}
}

sub DESTROY {
	my ($self) = @_;
	$log->debug("Calling CMU::ActiveMQ::DESTROY(self)");

	if ( defined $self->{_stomp} ) {
		$self->{_stomp}->disconnect();
		undef $self->{_stomp};
	}
}

1;
