#Copyright 2014 Carnegie Mellon University
#All rights reserved.

#Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

#1. Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.

#2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.

#3. Neither the name of the copyright holder nor the names of its contributors may be used to endorse or promote products derived from this software without specific prior written permission.

#THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

our %_CFG = (
	'ldap' => {
		'env'         => '389',
		'logtoerrorqueue' => 0
	},
	'AD' => {
		'server' => 'ldap',
		'port'   => '389',
		'binddn'     => 'cn=Directory Manager',
		'password'   => 'password',
		'syncou'     => 'ou=groups,dc=example,dc=edu',
		'peoplebase' => 'dc=example,dc=edu',
		'groupobjectclass'  => 'group',
		'personobjectclass' => 'person',
		'memberattribute'   => 'member',
		'dnattribute'       => 'distinguishedName',
		'memberprefix'      => 'uid=',
		'groupprefix'       => 'cn='
	},
	'389' => {
		'server' => [
			'ldap'
		],
		'port'       => '389',
		'binddn'     => 'cn=Directory Manager',
		'password'   => 'password',
		'syncou'     => 'ou=groups,dc=example,dc=edu',
		'peoplebase' => 'ou=People,dc=example,dc=edu',
		'groupobjectclass'  => 'groupOfUniqueNames',
		'personobjectclass' => 'person',
		'memberattribute'   => 'uniquemember',
		'dnattribute'       => 'entrydn',
		'memberprefix'      => 'uid=',
		'groupprefix'       => 'cn='
	},
	'activemq' => {
		'primary'     => 'activemq',
		'secondary'   => 'activemq',
		'port'        => '61613',
		'login'       => 'system',
		'password'    => 'manager',
		'ldapqueue' => '/queue/ldap.isMemberOf',
		'errorqueue' => '/queue/389.provisioner.errors',
	},
    'batchsize' => 500,
	'log' => {
		'file' =>
		  '/opt/amq_ldap_provisioner/conf/log4perl.conf'
	}
);
