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
		'server' => 'pdc.ad.example.edu',
		'port'   => '636',
		'binddn' =>
'CN=Grouper Service,OU=Service Accounts,DC=ad,DC=example,DC=edu',
		'password'   => 'xxxxxxxxx',
		'syncou'     => 'OU=GroupSync,DC=ad,DC=example,DC=edu',
		'peoplebase' => 'OU=Users,DC=ad,DC=example,DC=edu',
		'groupobjectclass'  => 'group',
		'personobjectclass' => 'person',
		'memberattribute'   => 'member'
		'dnattribute'       => 'distinguishedName',
		'memberprefix'      => 'cn=',
		'groupprefix'       => 'cn='
	},
	'389' => {
		'server' => [
			'master-01.ldap.example.edu', 'master-02.ldap.example.edu'
		],
		'port'       => '636',
		'binddn'     => 'uid=grouper,ou=serviceaccounts,dc=example,dc=edu',
		'password'   => 'xxxxxxxx',
		'syncou'     => 'ou=groups,dc=example,dc=edu',
		'peoplebase' => 'dc=example,dc=edu',
		'groupobjectclass'  => 'groupOfUniqueNames',
		'personobjectclass' => 'person',
		'memberattribute'   => 'uniquemember'
		'dnattribute'       => 'entryDN',
		'memberprefix'      => 'uid=',
		'groupprefix'       => 'cn='
	},
	'activemq' => {
		'primary'     => 'activemq-01.example.edu',
		'secondary'   => 'activemq-02.example.edu',
		'port'        => '61612',
		'login'       => 'activemq',
		'password'    => 'xxxxxxxx',
		'ldapqueue' => '/queue/test.389.groups',
		'errorqueue' => '/queue/389.provisioner.errors',
	},
    'batchsize' => 500,
	'log' => {
		'file' =>
		  '/opt/amq_ldap_provisioner/conf/log4perl.conf'
	}
);
