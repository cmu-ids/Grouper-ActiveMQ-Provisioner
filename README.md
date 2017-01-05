# AD/LDAP ActiveMQ Grouper Provisioner


### Features
The AD/LDAP ActiveMQ Grouper provisioner has the following features:

* Supports multiple provisioner instances/configurations.
* Fine-grain control over which groups are provisioned.
* Support of blocking group provisioning where group has more than X members.
* Utilizes ActiveMQ queues to support individual service provisioning.
* Supports AD, LDAP groups, and LDAP IsMemberOf provisioning.
* Includes support for renaming groups (wasn't included in original code base).



### Instructions

#### Change Log Consumer
* Add the change log consumer jar file to lib/custom along with other jar files from lib. Alternately, they can exist in their own directory if added to the class path.

* Setup ActiveMQ queues. 
You will need a separate queue for each service (AD, LDAP, LDAP IsMemberOf, other service). We are currently supporting AD and LDAP IsMemberOf (berkeleyEduIsMemberOf). A queue name is ldap.isMemberOf

* Configure attributes for each provisioning target within Grouper. Example:
The Grouper UI utilizes a separate plug-in for setting the provisioning attribute. See  <https://github.com/Unicon/grouper-provisioning-target-ui>. This attribute is used to determine provisioning for LDAP IsMemberOf attribute. Access to the sync attribute setting is allowed for most department group admins.

   * etc:attribute:provisioningTargets:all:syncToLdapIMO

   The attribute for allowLargeGroups should be only set by admin staff.

   * etc:attribute:provisioningTargets:all:allowLargeGroups

* Add configuration info to grouper-loader.properties file. Example for LDAP IsMemberOf provisioning:
````
changeLog.consumer.ldapIMO.class = edu.cmu.grouper.changelog.consumer.ConsumerMain
changeLog.consumer.ldapIMO.quartzCron = 0 * * * * ?
# ActiveMQ queue name
changeLog.consumer.ldapIMO.targets=ldap.isMemberOf
changeLog.consumer.ldapIMO.brokerURL=failover:(ssl://amq-t1.calnet.1918.berkeley.edu:61617,ssl://amq-t1.calnet.1918.berkeley.edu:61617)?randomize=false
changeLog.consumer.ldapIMO.username=grouper
changeLog.consumer.ldapIMO.password=
changeLog.consumer.ldapIMO.maxMembers=1000
changeLog.consumer.ldapIMO.syncAttribute=etc:attribute:provisioningTargets:all:syncToLdapIMO
changeLog.consumer.ldapIMO.allowLargeGroupsAttribute=etc:attribute:provisioningTargets:all:allowLargeGroups
# syncType is either basic or isMemberOf, default is basic
changeLog.consumer.ldapIMO.syncType=isMemberOf
# useXmlMessageFormat is true or false, default is true, alternate format is JSON
changeLog.consumer.ldapIMO.useXmlMessageFormat=false
````



#### AD/LDAP/IsMemberOf Provisioning
Setup separate directories for each downstream component. For example, AD, LDAP, LDAP IsMemberOf. Setup configuration files to connect with downstream servers and appropriate ActiveMQ queues. Add a start/stop script for each. We are using AD and LDAP IsMemberOF.

Example configuration:
````
our %_CFG = (
        'ldap' => {
                'env'         => '389',
                'logtoerrorqueue' => 1
        },
        'AD' => {
                'server' => 'campus.berkeley.edu',
                'port'   => '636',
                'binddn' => 'CN=Grouper Service,OU=Service Accounts,DC=ad,DC=example,DC=edu',
                'password'   => 'xxxxxxxxx',
                'syncou'     => 'OU=GroupSync,DC=ad,DC=example,DC=edu',
                'peoplebase' => 'OU=Users,DC=ad,DC=example,DC=edu',
                'groupobjectclass'  => 'group',
                'personobjectclass' => 'person',
                'memberattribute'   => 'member',
                'dnattribute'       => 'distinguishedName',
                'memberprefix'      => 'cn=',
                'groupprefix'       => 'cn='
        },
        '389' => {
                'server'     => 'nds-d1.calnet.1918.berkeley.edu',
                'port'       => '636',
                'binddn'     => 'uid=ist-is-ias-calgroups,ou=applications,dc=berkeley,dc=edu',
                'password'   => 'xxxxxxxx',
                'syncou'     => 'ou=campus groups,dc=berkeley,dc=edu',
                'peoplebase' => 'dc=berkeley,dc=edu',
                'groupobjectclass'  => 'groupOfUniqueNames',
                'personobjectclass' => 'person',
                'memberattribute'   => 'uniquemember',
                'dnattribute'       => 'entryDN',
                'memberprefix'      => 'uid=',
                'groupprefix'       => 'cn='
        },
        'activemq' => {
                'primary'     => 'amq-t1.calnet.1918.berkeley.edu',
                'secondary'   => 'amq-t1.calnet.1918.berkeley.edu',
                'port'        => '61613',
                'login'       => 'grouper',
                'password'    => 'xxxxxxxxx',
                'ldapqueue' => '/queue/ldap.isMemberOf',
                'errorqueue' => '/queue/ldap.IMO.errors',
        },
    'batchsize' => 500,
        'log' => {
                'file' =>
                  '/apps/ldapIMO/conf/log4perl.conf'
        }
);
````


#### Major changes from CMU code
The CMU code was designed to quickly push all the changes onto one queue. That queue was read by another app called grouperDispatcher. Based upon some configuration info, it would parse the queue items into other queues which were read by the provisioning apps. This method alllowed message redirection based only upon the path and names of the groups. 

We wanted group admins to determine in a yes/no interface whether or not a group should be provisioned to a downstream service. This allows the admin flexibility of setting up their group before turning on provisioning which potentially keeps the chatter down on the queues. While syncing attribute can be set on a stem, that can only be done by grouper service admins. Another advantage of using a sync attribute over just a groups name, is that one doesn't have to follow a specific naming convention. The group admins just determine for themselves which groups are provisioned to individual downstream services. 

The grouperDispatcher code was removed and individual changeLogConsumer instances were implemented utilizing the syncing attributes. This functionality needs to be in the changeLogConsumer, since it can read the attributes set on the groups/stems.

### Acknowledgements
Carnegie Melon for original code base. See <https://github.com/cmu-ids/Grouper-ActiveMQ-Provisioner>.

### Work still to complete
There are still a few items to complete. 

* Add more tests
* Add support for Stem name changes in AD. This will require an additional message within the changeLogConsumer and provisioners.
* Add support for removing stems that no longer have groups within AD since it uses a bushy name structure.
* Add sync attribute and large group support to full sync methods.
* After going through the grouper/googleapps code changes that the grouper project added, I see their solution for the delete group issue using PIT table is the better way to go. We should use this in this code base. 
