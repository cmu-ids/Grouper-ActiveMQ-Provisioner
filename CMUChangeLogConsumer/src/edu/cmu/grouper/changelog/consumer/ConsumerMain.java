/*Copyright 2014 Carnegie Mellon University
All rights reserved.

Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

1. Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.

2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.

3. Neither the name of the copyright holder nor the names of its contributors may be used to endorse or promote products derived from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.*/

package edu.cmu.grouper.changelog.consumer;

import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Set;

import javax.jms.Connection;
import javax.jms.DeliveryMode;
import javax.jms.Destination;
import javax.jms.MessageProducer;
import javax.jms.Session;
import javax.jms.TextMessage;

import org.apache.activemq.ActiveMQConnectionFactory;
import org.apache.commons.cli.CommandLine;
import org.apache.commons.cli.CommandLineParser;
import org.apache.commons.cli.GnuParser;
import org.apache.commons.cli.HelpFormatter;
import org.apache.commons.cli.Options;
import org.apache.commons.cli.ParseException;
import org.apache.commons.logging.Log;
import org.apache.commons.logging.LogFactory;

import edu.internet2.middleware.grouper.Group;
import edu.internet2.middleware.grouper.Stem;
import edu.internet2.middleware.grouper.Stem.Scope;
import edu.internet2.middleware.grouper.StemFinder;
import edu.internet2.middleware.grouper.GroupFinder;
import edu.internet2.middleware.grouper.GroupTypeFinder;
import edu.internet2.middleware.grouper.GrouperSession;
import edu.internet2.middleware.grouper.Member;
import edu.internet2.middleware.grouper.MemberFinder;
import edu.internet2.middleware.grouper.SubjectFinder;
import edu.internet2.middleware.grouper.changeLog.ChangeLogConsumerBase;
import edu.internet2.middleware.grouper.changeLog.ChangeLogEntry;
import edu.internet2.middleware.grouper.changeLog.ChangeLogLabels;
import edu.internet2.middleware.grouper.changeLog.ChangeLogProcessorMetadata;
import edu.internet2.middleware.grouper.changeLog.ChangeLogTypeBuiltin;
import edu.internet2.middleware.subject.Subject;
import edu.internet2.middleware.grouper.attr.AttributeDefName;
import edu.internet2.middleware.grouper.attr.finder.AttributeDefNameFinder;
import edu.internet2.middleware.grouper.attr.finder.AttributeAssignFinder;
import edu.internet2.middleware.grouper.attr.assign.AttributeAssign;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import org.json.simple.JSONArray;
import org.json.simple.JSONObject;



/**
 * Class to dispatch individual events
 */
public class ConsumerMain extends ChangeLogConsumerBase {

	private static final Logger LOG = LoggerFactory.getLogger(edu.cmu.grouper.changelog.consumer.ConsumerMain.class);
	//private static final Log LOG = LogFactory
	//		.getLog(edu.cmu.grouper.changelog.consumer.ConsumerMain.class);
	private GrouperSession gs;
	private ActiveMQConnectionFactory connectionFactory;
	private static Connection connection;	
	// Allow large groups is this is set to yes
	private static AttributeDefName allowLargeGroupsAttribute;
	// This is the maximum members to allow for a group to be provisioned
	private static int maxMembers;
	private static AttributeDefName syncAttribute;
	private static String consumerName;
	private static boolean basicSyncType;
	private static boolean iMOSyncType;
	private static boolean useXmlMessageFormat;
	private HashMap<String, String> syncedObjects;
	long currentId = 0;
	
	

	/**
	 * @see ChangeLogConsumerBase#processChangeLogEntries(List,
	 *      ChangeLogProcessorMetadata)
	 */
	@Override
	public long processChangeLogEntries(
			List<ChangeLogEntry> changeLogEntryList,
			ChangeLogProcessorMetadata changeLogProcessorMetadata) {

		String brokerURL;
		String username;
		String password;
		
		// initialize this consumer's consumerName from the change log metadata
        if (consumerName == null) {
            consumerName = changeLogProcessorMetadata.getConsumerName();
            LOG.debug("CMU Consumer Name '{}' - Setting name.", consumerName);
        }
        
		ConsumerProperties properties = new ConsumerProperties(consumerName);

		brokerURL = properties.getBrokerUrl();
		username = properties.getUsername();
		password = properties.getPassword();
		maxMembers = properties.getMaxMembers();
		// This is the attribute to use to know if we should send this change to the queue.
		syncAttribute = AttributeDefNameFinder.findByName( properties.getSyncAttribute(), true);
		// This is the attribute to use to know if we should allow large groups over maxMembers
		allowLargeGroupsAttribute = AttributeDefNameFinder.findByName( properties.getAllowLargeGroupsAttribute(), true);
		// Should we send this to the basic type queue   equalsIgnoreCase
		basicSyncType = properties.getSyncType().equalsIgnoreCase("basic") ? true : false;
		// Should we send this to the isMemberOf type queue.
		iMOSyncType = properties.getSyncType().equalsIgnoreCase("isMemberOf") ? true : false;
		// What outgoing message format shall we use. xml or json
		useXmlMessageFormat = properties.getUseXmlMessageFormat();
		// Setup Synced Object HashMap. 
		syncedObjects = new HashMap<String, String>();
		
		

		for (ChangeLogEntry changeLogEntry : changeLogEntryList) {
			currentId = changeLogEntry.getSequenceNumber();
			break;
		}

		try {
			// Create a Connection Factory and connection
			connectionFactory = new ActiveMQConnectionFactory(username,
					password, brokerURL);
			connection = connectionFactory.createConnection();
			connection.start();
		} catch (Exception e) {
			LOG.error("Error connecting to ActiveMQ " + e.getMessage()
					+ " Sequence:" + currentId);
			return currentId - 1;
		}

		try {
			// get the existing Grouper session from the loader
			gs = GrouperSession.staticGrouperSession();
			if (gs == null) {
				LOG.error("Couldn't process any records: Unable to get grouper session "
						+ currentId);
				return currentId - 1;
			}
			
			for (ChangeLogEntry changeLogEntry : changeLogEntryList) {
				Member member;
				String groupName;

				currentId = changeLogEntry.getSequenceNumber();

				LOG.debug("Processing sequence: "
						+ changeLogEntry.getSequenceNumber()
						+ " ChangeLogType: "
						+ changeLogEntry.getChangeLogType());

				if (changeLogEntry
						.equalsCategoryAndAction(ChangeLogTypeBuiltin.GROUP_ADD)) {
					groupName = changeLogEntry
							.retrieveValueForLabel(ChangeLogLabels.GROUP_ADD.name);
					

					if (groupName == null) {
						LOG.error("No group name for group add change type. Skipping sequence: "
								+ currentId);
					} else {
						if (groupOk(groupName) && basicSyncType) {
							String mesg = getGroupAddedMessage(groupName);
							writeMessage(mesg, groupName, currentId);
						} else {
						   LOG.info ("group " + groupName + " will not be added.");
						}					
					}
				} else if (changeLogEntry
						.equalsCategoryAndAction(ChangeLogTypeBuiltin.GROUP_UPDATE)) {
					groupName = changeLogEntry
							.retrieveValueForLabel(ChangeLogLabels.GROUP_UPDATE.name);
					String groupDescription = changeLogEntry
							.retrieveValueForLabel(ChangeLogLabels.GROUP_UPDATE.description);

					if (groupName == null) {
						LOG.error("No group name for group update change type. Skipping sequence: "
								+ currentId);
					} else {
						if (groupOk(groupName)) {
							String propertyChanged = changeLogEntry
									.retrieveValueForLabel(ChangeLogLabels.GROUP_UPDATE.propertyChanged);
							if (propertyChanged.equals("description")) {
								String groupOldDescription = changeLogEntry
										.retrieveValueForLabel(ChangeLogLabels.GROUP_UPDATE.propertyOldValue);
								if (groupOldDescription == null) {
									groupOldDescription = "";
								}
								if (basicSyncType) {
									String mesg = getGroupUpdatedMessage(groupName, groupDescription, groupOldDescription);
									writeMessage(mesg, groupName, currentId);
								}
							} else if (propertyChanged.equals("name")) {
								String groupOldName = changeLogEntry
										.retrieveValueForLabel(ChangeLogLabels.GROUP_UPDATE.propertyOldValue);
								if (basicSyncType) {
									String mesg = getGroupRenamedMessage(groupName, groupOldName);
									writeMessage(mesg, groupName, currentId);
								}
								if (iMOSyncType) {
									String mesgIsMemberOf = getGroupIsMemberOfRenamedMessage(groupName, groupOldName);
									writeMessage(mesgIsMemberOf, groupName, currentId);
								}
							} else {
								LOG.debug("Skipping sequence "
										+ changeLogEntry.getSequenceNumber()
										+ " as group update property: "
										+ propertyChanged + " is not handled");
							}
						}
					}
				} else if (changeLogEntry
						.equalsCategoryAndAction(ChangeLogTypeBuiltin.GROUP_DELETE)) {
					groupName = changeLogEntry
							.retrieveValueForLabel(ChangeLogLabels.GROUP_DELETE.name);							
					deleteGroup (groupName);
					
				} else if (changeLogEntry
						.equalsCategoryAndAction(ChangeLogTypeBuiltin.MEMBERSHIP_ADD)) {
					groupName = changeLogEntry
							.retrieveValueForLabel(ChangeLogLabels.MEMBERSHIP_ADD.groupName);
					member = getMemberFromId(changeLogEntry
							.retrieveValueForLabel(ChangeLogLabels.MEMBERSHIP_ADD.memberId));

					if (groupName == null) {
						LOG.error("No group name for membership add change type. Skipping sequence:"
								+ currentId);
					} else {
						if (groupOk(groupName)) {
							if (member != null) {
								String memberName = null;
							
								if (member.getSubjectType().toString()
										.equals("person")) {
									memberName = member.getSubjectId();
									if (iMOSyncType) {
										String mesgIsMemberOf = getIsMemberOfAddedMessage(
												groupName, memberName);
										writeMessage(mesgIsMemberOf, groupName,
												currentId);
									}
								} else {
									memberName = member.getName();
								}
								if (basicSyncType) {
									String mesg = getGroupMemberAddedMessage(groupName,memberName);
									writeMessage(mesg, groupName, currentId);
								}
							}
						}
					}
				} else if (changeLogEntry
						.equalsCategoryAndAction(ChangeLogTypeBuiltin.MEMBERSHIP_DELETE)) {
					groupName = changeLogEntry
							.retrieveValueForLabel(ChangeLogLabels.MEMBERSHIP_DELETE.groupName);
					member = getMemberFromId(changeLogEntry
							.retrieveValueForLabel(ChangeLogLabels.MEMBERSHIP_DELETE.memberId));

					if (groupName == null) {
						LOG.error("No group name for membership delete change type. Skipping sequence: "
								+ currentId);
					} else {
						if (groupOk(groupName)) {
							if (member != null) {
								String memberName = null;
								
								if (member.getSubjectType().toString()
										.equals("person")) {
									memberName = member.getSubjectId();
									if (iMOSyncType) {
										String mesgIsMemberOf = getIsMemberOfDeletedMessage(
												groupName, memberName);
										writeMessage(mesgIsMemberOf, groupName,
												currentId);
									}
								} else {
									memberName = member.getName();
								}
								if (basicSyncType) {
									String mesg = getGroupMemberDeletedMessage(groupName, memberName);
									writeMessage(mesg, groupName, currentId);
								}
							}
						}
					}
				} else if (changeLogEntry
						.equalsCategoryAndAction(ChangeLogTypeBuiltin.PRIVILEGE_ADD)
						&& (changeLogEntry.retrieveValueForLabel(
								ChangeLogLabels.PRIVILEGE_ADD.privilegeName)
								.equals("admin") || changeLogEntry
								.retrieveValueForLabel(
										ChangeLogLabels.PRIVILEGE_ADD.privilegeName)
								.equals("update"))) {
					groupName = changeLogEntry
							.retrieveValueForLabel(ChangeLogLabels.PRIVILEGE_ADD.ownerName);

					member = getMemberFromId(changeLogEntry
							.retrieveValueForLabel(ChangeLogLabels.PRIVILEGE_ADD.memberId));

					if (groupName == null) {
						LOG.error("No group name for privilege add change type. Skipping sequence: "
								+ currentId);
					} else {
						if (groupOk(groupName)) {
							if (member != null) {
								String memberName = null;
								if (basicSyncType) {
								   if (member.getSubjectType().toString()
										.equals("person")) {
										memberName = member.getSubjectId();
									//String mesgPrivilegeAdd = getPrivilegeAddedMessage(
									//		groupName, memberName);
									//writeMessage(mesgPrivilegeAdd, groupName,
									//		currentId);
									} else {
										memberName = member.getName();
									}
									String mesg = getPrivilegeAddedMessage(groupName,
												memberName);
									writeMessage(mesg, groupName, currentId);
								}
							}
						}
					}
				} else if (changeLogEntry
						.equalsCategoryAndAction(ChangeLogTypeBuiltin.PRIVILEGE_DELETE)
						&& (changeLogEntry.retrieveValueForLabel(
								ChangeLogLabels.PRIVILEGE_ADD.privilegeName)
								.equals("admin") || changeLogEntry
								.retrieveValueForLabel(
										ChangeLogLabels.PRIVILEGE_ADD.privilegeName)
								.equals("update"))) {
					groupName = changeLogEntry
							.retrieveValueForLabel(ChangeLogLabels.PRIVILEGE_DELETE.ownerName);

					member = getMemberFromId(changeLogEntry
							.retrieveValueForLabel(ChangeLogLabels.PRIVILEGE_DELETE.memberId));

					if (groupName == null) {
						LOG.error("No group name for privilege add change type. Skipping sequence: "
								+ currentId);
					} else {
						if (groupOk(groupName)) {
							if (member != null) {
								String memberName = null;
								
								if (member.getSubjectType().toString()
										.equals("person")) {
									memberName = member.getSubjectId();
									//String mesgPrivilegeDelete = getPrivilegeDeletedMessage(
									//		groupName, memberName);
									//writeMessage(mesgPrivilegeDelete, groupName,
									//		currentId);
								} else {
									memberName = member.getName();
								}
								if (basicSyncType) {
									String mesg = getPrivilegeDeletedMessage(groupName,
											memberName);
									writeMessage(mesg, groupName, currentId);
								}
							}
						}
					}
				} else if (changeLogEntry
							.equalsCategoryAndAction(ChangeLogTypeBuiltin.ATTRIBUTE_ASSIGN_VALUE_ADD)) {

					final String attributeDefNameId = 
								changeLogEntry.retrieveValueForLabel(ChangeLogLabels.ATTRIBUTE_ASSIGN_VALUE_ADD.attributeDefNameId);
			        final String value = changeLogEntry.retrieveValueForLabel(ChangeLogLabels.ATTRIBUTE_ASSIGN_VALUE_ADD.value);
					
					AttributeAssign theAttributeAssign = AttributeAssignFinder.findById(	
							changeLogEntry.retrieveValueForLabel(ChangeLogLabels.ATTRIBUTE_ASSIGN_VALUE_ADD.attributeAssignId), false);
					final Group theGroup = theAttributeAssign != null ? theAttributeAssign.getOwnerGroup() : null;
					boolean isGroup = (theGroup != null) ? true : false;
					final Stem theStem = theAttributeAssign != null ? theAttributeAssign.getOwnerStem() : null;
					boolean isStem = (theStem != null) ? true : false;
					
	
					// The value is set to yes
					if (value.equalsIgnoreCase("yes")) {
						// This is the Sync or Allow Large Groups Attribute
						if (syncAttribute.getId().equalsIgnoreCase(attributeDefNameId) || 
								allowLargeGroupsAttribute.getId().equalsIgnoreCase(attributeDefNameId)) {
							if (isGroup) {
								if (groupOk (theGroup.getName())){
									syncGroup(theGroup);
								}
							} else if (isStem) {
								final Set<edu.internet2.middleware.grouper.Group> groups = theStem.getChildGroups(Scope.SUB);

				                for (edu.internet2.middleware.grouper.Group group : groups) {
									if (groupOk (group.getName())) {
				                   		syncGroup(group);
									}
								}
							}
						}
					}
					// The value is set to no
					if (value.equalsIgnoreCase("no")) {
						// This is the Sync Attribute
						if (syncAttribute.getId().equalsIgnoreCase(attributeDefNameId) || 
								allowLargeGroupsAttribute.getId().equalsIgnoreCase(attributeDefNameId)) {
							if (isGroup) {
								if (shouldDelete (theGroup.getName())) {
									deleteGroup (theGroup.getName());
								}
							} else if (isStem) {
								final Set<edu.internet2.middleware.grouper.Group> groups = theStem.getChildGroups(Scope.SUB);

				                for (edu.internet2.middleware.grouper.Group group : groups) {
									if (shouldDelete (group.getName())) {
				                   		deleteGroup (group.getName());
									}
								}
							}
						}
					}	
													
				} else {
					LOG.debug("Skipping sequence: "
							+ changeLogEntry.getSequenceNumber()
							+ " as changelog type "
							+ changeLogEntry.getChangeLogType()
							+ " is not handled");
				}

				LOG.debug("Sucessfully processed sequence: "
						+ changeLogEntry.getSequenceNumber());
			}
		} catch (Exception e) {
			LOG.error("Error processing sequence " + currentId, e);
			changeLogProcessorMetadata.registerProblem(e,
					"Error processing sequence " + currentId, currentId);

			return currentId - 1;
		} finally {
			if (connection != null) {
				try {
					connection.close();
				} catch (Exception e) {
					LOG.error("Error closing ActiveMQ connection" + currentId,
							e);
					return currentId - 1;
				}
			}
		}

		return currentId;
	}
	
	
	private boolean groupOk (String groupName) {
		LOG.debug ("groupOk (groupName: {})", groupName);

		// Check if group exists
		Group group = GroupFinder.findByName(gs, groupName, false);
	    if (group == null) {
			LOG.debug("Group " + groupName + " doesn\'t exist");
			return false;
        }

		if (syncedObjects.containsKey(groupName)) {
			if (syncedObjects.get(groupName).equalsIgnoreCase("yes")) return true;
		}
		
  	    // Check if the sync attribute exists and is "yes"
		// plus membership size is less than maxMembers
		if (isAttributeSetToYes (group, syncAttribute)) {
			if (group.getMembers().size() <= maxMembers) {
				LOG.debug("Group {} is okay to provision or add a member. Size is {}", groupName, group.getMembers().size()); 
				syncedObjects.put(groupName, "yes");
            	return true;
			} else {
				if (isAttributeSetToYes (group, allowLargeGroupsAttribute)) {
					LOG.debug("Group {} is okay to provision or add a member due to allowLargeGroups attribute being set", groupName);
					syncedObjects.put(groupName, "yes");
					return true;
				}
				return false;
			}
		} else {
			// The group doesn't have sync = yes
			LOG.debug ("No go for group {}", groupName);
			return false;
		}
	} 


	private boolean shouldDelete (String groupName) {
		LOG.debug ("shouldDelete (groupName: {})", groupName);
				
		// Check if group exists
		Group group = GroupFinder.findByName(gs, groupName, false);
	    if (group == null) {
			LOG.debug("Group " + groupName + " doesn\'t exist");
			return true;
        }
  	    // Check if the sync attribute exists and is "yes"
		// plus membership size is less than maxMembers
		if (isAttributeSetToYes (group, syncAttribute)) {
			if (group.getMembers().size() <= maxMembers) {
				LOG.debug("Group {} should remain. Size is {}", groupName, group.getMembers().size()); 
            	return false;
			} else {
				if (isAttributeSetToYes (group, allowLargeGroupsAttribute)) {
					LOG.debug("Group {} should remain or add a member due to allowLargeGroups attribute being set", groupName);
					return false;
				}
				return true;
			}
		} else {
			// The group doesn't have sync = yes
			LOG.debug ("We are go for deletion group {}", groupName);
			return true;
		}
	} 



	private boolean isAttributeSetToYes(Group group, AttributeDefName attribute) {
		LOG.debug ("isAttributeSetToYes (group: {}, attribute: {})", group, attribute);
		
		if (group.getAttributeDelegate().retrieveAssignments(attribute).size() > 0) {
			return group.getAttributeDelegate().retrieveAssignments(attribute)
									.iterator().next().getValueDelegate().retrieveValuesString().contains("yes") ||
						isAttributeSetToYesOnStem (group.getParentStem(), attribute);
		// The attribute isn't set. We'll check the Stem.
		} else {
			return isAttributeSetToYesOnStem (group.getParentStem(), attribute);
		}
	}


	private boolean isAttributeSetToYesOnStem (Stem stem, AttributeDefName attribute) {
		LOG.debug ("isAttributeSetToYes (stem: {}, attribute: {})", stem, attribute);

        final String stemName = stem.getName();

		if (stem.getAttributeDelegate().retrieveAssignments(attribute).size() > 0) {
			return stem.getAttributeDelegate().retrieveAssignments(attribute)
									.iterator().next().getValueDelegate().retrieveValuesString().contains("yes");
		// Try the parent stem if we aren't already at the root stem.
		} else {
			return !stem.isRootStem() && isAttributeSetToYesOnStem (stem.getParentStem(), attribute);
		}
    }

	private void deleteGroup (String groupName) {
		LOG.debug ("deleteGroup (groupName {})", groupName);
		if (groupName == null) {
			LOG.error("No group name for group delete change type. Skipping to next in sequence.");
		} else {
			if (basicSyncType) {
				String mesg = getGroupDeletedMessage(groupName);
				writeMessage(mesg, groupName, currentId);
			}
			if (iMOSyncType) {
				String mesgIsMemberOf = getGroupDeletedIsMemberOfMessage(groupName);						
				writeMessage(mesgIsMemberOf, groupName, currentId);
			}
		syncedObjects.remove(groupName);
		}
		
	}
	
	private void syncGroup(Group group) {
		LOG.debug ("syncGroup(group {})", group);
		if (group != null) {
			LOG.debug("Sync for group {}.", group.getName());
			
			Set<Member> members = getAllGroupMembers(group, gs);
			
			if (basicSyncType) {
				String mesg = getGroupFullSyncMessage(group, members);
				LOG.debug("GroupFullSyncMesg: {}", mesg);
				writeMessage(mesg, group.getName(), currentId);
			}
			if (iMOSyncType) {
				String mesgIsMemberOf = getIsMemberOfFullSyncMessage(group, members);
				LOG.debug("isMemberOfSyncMessage: ", mesgIsMemberOf);
				writeMessage(mesgIsMemberOf, group.getName(), currentId);
			}

			LOG.info("Group Sync completed sucessfully for group "
					+ group.getName());

		} else {
			LOG.debug("Group {} not found", group.getName());
		}
	}
		
	private Set<Member> getAllGroupMembers(Group group) {
		Set<Member> members = new HashSet<Member>();

		Set<Member> group_members = group.getMembers();

		for (Member member : group_members) {
			String memberType = member.getSubjectType().toString();
			if (memberType.equals("person")) {
				members.add(member);
			} else if (memberType.equals("group")) {
				Subject subject = member.getSubject();

				if (subject != null) {
					members.add(member);
					Group nested_group = GroupFinder.findByName(gs,
							member.getName(), false);
					Set<Member> nested_group_members = getAllGroupMembers(
							nested_group, gs);

					for (Member nested_member : nested_group_members) {
						members.add(nested_member);
					}
				} else {
					LOG.error("Cannot find group:" + member.getName());
				}

			}
		}
		return members;
	}
		
		
   

	private String getGroupAddedMessage(String groupName) {
		String mesg = "";
		if (useXmlMessageFormat) {
			mesg = "<operation>createGroup</operation>";
			mesg = mesg + "<name><![CDATA[" + groupName + "]]></name>";
		} else {
			mesg = "{\"operation\":\"createGroup\",";
			mesg = mesg + "\"name\":\"" + groupName + "\"}";
		}
		return mesg;
	}

	private String getGroupDeletedMessage(String groupName) {
		String mesg = "";
		if (useXmlMessageFormat) {
			mesg = "<operation>deleteGroup</operation>";
			mesg = mesg + "<name><![CDATA[" + groupName + "]]></name>";
		} else {
			mesg = "{\"operation\":\"deleteGroup\",";
			mesg = mesg + "\"name\":\"" + groupName + "\"}";
		}
		return mesg;
	}

	private String getGroupDeletedIsMemberOfMessage(String groupName) {
		String mesg = "";
		if (useXmlMessageFormat) {
			mesg = "<operation>deleteGroupIsMemberOf</operation>";
			mesg = mesg + "<name><![CDATA[" + groupName + "]]></name>";
		} else {
			mesg = "{\"operation\":\"deleteGroupIsMemberOf\",";
			mesg = mesg + "\"name\":\"" + groupName + "\"}";
		}
		return mesg;
	}

	private String getGroupUpdatedMessage(String groupName,
			String groupDescription, String groupOldDescription) {
		String mesg = "";
		if (useXmlMessageFormat) {
			mesg = "<operation>updateGroup</operation>";
			mesg = mesg + "<name><![CDATA[" + groupName + "]]></name>";
			mesg = mesg + "<description><![CDATA[" + groupDescription
					+ "]]></description>";
			mesg = mesg + "<olddescription><![CDATA[" + groupOldDescription
				+ "]]></olddescription>";
		} else {
			mesg = "{\"operation\":\"updateGroup\",";
			mesg = mesg + "\"name\":\"" + groupName + "\",";
			mesg = mesg + "\"description\":\"" + groupDescription + "\",";
			mesg = mesg + "\"olddescription\":\"" + groupOldDescription + "\"}";
		}
		return mesg;
	}

	private String getGroupRenamedMessage(String groupName, String groupOldName) {
		String mesg = "";
		if (useXmlMessageFormat) {
			mesg = "<operation>renameGroup</operation>";
			mesg = mesg + "<name><![CDATA[" + groupName + "]]></name>";
			mesg = mesg + "<oldname><![CDATA[" + groupOldName + "]]></oldname>";
		} else {
			mesg = "{\"operation\":\"renameGroup\",";
			mesg = mesg + "\"name\":\"" + groupName + "\",";
			mesg = mesg + "\"oldname\":\"" + groupOldName + "\"}";
		}
		return mesg;
	}

	private String getGroupIsMemberOfRenamedMessage(String groupName, String groupOldName) {
		String mesg = "";
		if (useXmlMessageFormat) {
			mesg = "<operation>renameGroupIsMemberOf</operation>";
			mesg = mesg + "<name><![CDATA[" + groupName + "]]></name>";
			mesg = mesg + "<oldname><![CDATA[" + groupOldName + "]]></oldname>";
		} else {
			mesg = "{\"operation\":\"deleteGroupIsMemberOf\",";
			mesg = mesg + "\"name\":\"" + groupName + "\",";
			mesg = mesg + "\"oldname\":\"" + groupOldName + "\"}";
		}
		return mesg;
	}

	private String getGroupMemberAddedMessage(String groupName, String uid) {
		String mesg = "";
		if (useXmlMessageFormat) {
			mesg = "<operation>addMember</operation>";
			mesg = mesg + "<name><![CDATA[" + groupName + "]]></name>";
			mesg = mesg + "<memberId><![CDATA[" + uid + "]]></memberId>";
		} else {
			mesg = "{\"operation\":\"addMember\",";
			mesg = mesg + "\"name\":\"" + groupName + "\",";
			mesg = mesg + "\"memberId\":\"" + uid + "\"}";
		}
		return mesg;
	}

	private String getIsMemberOfAddedMessage(String groupName, String uid) {
		String mesg = "";
		if (useXmlMessageFormat) {		
			mesg = "<operation>addIsMemberOf</operation>";
			mesg = mesg + "<name><![CDATA[" + groupName + "]]></name>";
			mesg = mesg + "<memberId><![CDATA[" + uid + "]]></memberId>";
		} else {
			mesg = "{\"operation\":\"addIsMemberOf\",";
			mesg = mesg + "\"name\":\"" + groupName + "\",";
			mesg = mesg + "\"memberId\":\"" + uid + "\"}";
		}
		return mesg;
	}

	private String getGroupMemberDeletedMessage(String groupName, String uid) {
		String mesg = "";
		if (useXmlMessageFormat) {
			mesg = "<operation>removeMember</operation>";
			mesg = mesg + "<name><![CDATA[" + groupName + "]]></name>";
			mesg = mesg + "<memberId><![CDATA[" + uid + "]]></memberId>";
		} else {
			mesg = "{\"operation\":\"removeMember\",";
			mesg = mesg + "\"name\":\"" + groupName + "\",";
			mesg = mesg + "\"memberId\":\"" + uid + "\"}";
		}
		return mesg;
	}

	private String getIsMemberOfDeletedMessage(String groupName, String uid) {
		String mesg = "";
		if (useXmlMessageFormat) {		
			mesg = "<operation>removeIsMemberOf</operation>";
			mesg = mesg + "<name><![CDATA[" + groupName + "]]></name>";
			mesg = mesg + "<memberId><![CDATA[" + uid + "]]></memberId>";
		} else {
			mesg = "{\"operation\":\"removeIsMemberOf\",";
			mesg = mesg + "\"name\":\"" + groupName + "\",";
			mesg = mesg + "\"memberId\":\"" + uid + "\"}";
		}
		return mesg;
	}

	private String getPrivilegeAddedMessage(String groupName, String uid) {
		String mesg = "";
		if (useXmlMessageFormat) {
			mesg = "<operation>addPrivilege</operation>";
			mesg = mesg + "<name><![CDATA[" + groupName + "]]></name>";
			mesg = mesg + "<memberId><![CDATA[" + uid + "]]></memberId>";
		} else {
			mesg = "{\"operation\":\"addPrivilege\",";
			mesg = mesg + "\"name\":\"" + groupName + "\",";
			mesg = mesg + "\"memberId\":\"" + uid + "\"}";
		}
		return mesg;
	}

	private String getPrivilegeDeletedMessage(String groupName, String uid) {
		String mesg = "";
		if (useXmlMessageFormat) {
			mesg = "<operation>removePrivilege</operation>";
			mesg = mesg + "<name><![CDATA[" + groupName + "]]></name>";
			mesg = mesg + "<memberId><![CDATA[" + uid + "]]></memberId>";
		} else {
			mesg = "{\"operation\":\"removePrivilege\",";
			mesg = mesg + "\"name\":\"" + groupName + "\",";
			mesg = mesg + "\"memberId\":\"" + uid + "\"}";
		}
		return mesg;
	}

	private static String getGroupFullSyncMessage(Group group,
			Set<Member> members) {
		String mesg = "";
		JSONObject jObj = new JSONObject();
		JSONArray jList = new JSONArray();
		
		if (useXmlMessageFormat) {
			mesg = "<operation>fullSync</operation>";
			mesg = mesg + "<description><![CDATA[" + group.getDescription()
					+ "]]></description>";
			mesg = mesg + "<name><![CDATA[" + group.getName() + "]]></name>";
			mesg = mesg + "<memberList>";

			for (Member member : members) {
				if (member.getSubjectType().toString().equals("group")) {
					mesg = mesg + "<member><![CDATA[" + member.getName()
							+ "]]></member>";
				} else {
					mesg = mesg + "<member><![CDATA[" + member.getSubjectId()
							+ "]]></member>";
				}
			}
			mesg = mesg + "</memberList>";
			
		} else {
			jObj.put ("operation", "fullSync");
			jObj.put ("description", group.getDescription());
			jObj.put ("name", group.getName());
			
			for (Member member : members) {
				if (member.getSubjectType().toString().equals("group")) {
					jList.add (member.getName());
				} else {
					jList.add (member.getSubjectId());
				}
			}
			jObj.put ("memberList", jList);
			mesg = jObj.toJSONString();	
		}
		return mesg;
	}

	private static String getGroupPrivilegeFullSyncMessage(Group group,
			Set<Subject> subjects) {
		String mesg = "";
		JSONObject jObj = new JSONObject();
		JSONArray jList = new JSONArray();
		
		if (useXmlMessageFormat) {		
			mesg = "<operation>fullSyncPrivilege</operation>";
			mesg = mesg + "<description><![CDATA[" + group.getDescription()
					+ "]]></description>";
			mesg = mesg + "<name><![CDATA[" + group.getName() + "]]></name>";
			mesg = mesg + "<memberList>";

			for (Subject subject : subjects) {
				if (subject.getSourceId().equals("ldap")){
					mesg = mesg + "<member><![CDATA[" + subject.getId()
								+ "]]></member>";
				} else {
					mesg = mesg + "<member><![CDATA[" + subject.getName()
								+ "]]></member>";
				}
			}
			mesg = mesg + "</memberList>";
		} else {
			jObj.put ("operation", "fullSyncPrivilege");
			jObj.put ("description", group.getDescription());
			jObj.put ("name", group.getName());

			for (Subject subject : subjects) {
				if (subject.getSourceId().equals("ldap")){
					jList.add (subject.getId());
				} else {
					jList.add (subject.getName());
				}
			}
			jObj.put ("memberList", jList);
			mesg = jObj.toJSONString();	
		}
		
		return mesg;
	}


	private static String getIsMemberOfFullSyncMessage(Group group,
			Set<Member> members) {
		String mesg = "";
		JSONObject jObj = new JSONObject();
		JSONArray jList = new JSONArray();
		
		if (useXmlMessageFormat) {		
			mesg = "<operation>fullSyncIsMemberOf</operation>";
			mesg = mesg + "<name><![CDATA[" + group.getName() + "]]></name>";
			mesg = mesg + "<memberList>";

			for (Member member : members) {
				if (member.getSubjectType().toString().equals("person")) {
					mesg = mesg + "<member><![CDATA[" + member.getSubjectId()
							+ "]]></member>";
				}
			}
			mesg = mesg + "</memberList>";
		} else {
			jObj.put ("operation", "fullSyncIsMemberOf");
			jObj.put ("name", group.getName());
			
			for (Member member : members) {
				if (member.getSubjectType().toString().equals("person")) {
					jList.add (member.getSubjectId());
				}
			}
			jObj.put ("memberList", jList);
			mesg = jObj.toJSONString();	
		}
		return mesg;
	}

	private static Set<Member> getAllGroupMembers(Group group,
			GrouperSession session) {
		Set<Member> members = new HashSet<Member>();

		Set<Member> group_members = group.getMembers();

		for (Member member : group_members) {
			String memberType = member.getSubjectType().toString();
			if (memberType.equals("person")) {
				members.add(member);
			} else if (memberType.equals("group")) {
				Subject subject = member.getSubject();

				if (subject != null) {
					members.add(member);
					Group nested_group = GroupFinder.findByName(session,
							member.getName(), false);
					Set<Member> nested_group_members = getAllGroupMembers(
							nested_group, session);

					for (Member nested_member : nested_group_members) {
						members.add(nested_member);
					}
				} else {
					LOG.error("Cannot find group:" + member.getName());
				}

			}
		}

		return members;

	}

	static public String getGroupAttribute(String groupName,
			String attributeName, Group group) {
		String result;

		// for delete, group may no longer exist
		if (group == null) {
			return "";
			// Note: addGroupInfo in the message writer will log an
			// error if the group does not exist
		}

		// try to get the attribute value
		try {
			result = group.getAttributeValue(attributeName, false, false);
			if (result == null)
				result = "";
		} catch (Exception e) {
			result = "";
			if (e instanceof edu.internet2.middleware.grouper.exception.AttributeNotFoundException) {
				// ignore if attribute is not defined
			} else {
				LOG.error("failed to get value of attribute " + attributeName
						+ " for group " + groupName + ": " + e);
			}
		}

		return result;
	}

	private Member getMemberFromId(String memberId) {
		Member member;
		member = MemberFinder.findByUuid(gs, memberId, false);
		return member;
	}

	private static void writeMessage(String mesg, String jmsxGroupId,
			long sequence) {
		String result = addToMessageQueue(mesg, jmsxGroupId, sequence);
		if (result.equals("OK")) {
			LOG.debug("Message sent OK for squence: " + sequence + " Message: "
					+ mesg);
		} else {
			throw new RuntimeException("Message send failed with result: "
					+ result + " Message: " + mesg);
		}
	}

	public static String addToMessageQueue(String grouperMessage,
			String jmsxGroupId, long sequence) {

		Destination destination;
		Session session;
		MessageProducer producer;
		TextMessage message;

		String result = "";
		session = null;
		producer = null;


		try {
			String delims = "[,]";
			String targets = ConsumerProperties.getTargets();
			String[] target = targets.split(delims);

			for (int i = 0; i < target.length; i++) {
				String targetQueue = target[i];
				session = connection.createSession(false,
						Session.AUTO_ACKNOWLEDGE);
				destination = session.createQueue(targetQueue);
				producer = session.createProducer(destination);
				producer.setDeliveryMode(DeliveryMode.PERSISTENT);

				// Queue the message
				message = session.createTextMessage(grouperMessage);
				message.setStringProperty("JMSXGroupID", jmsxGroupId);
				producer.send(message);

			}
		} catch (Exception e) {
			result = "Failed: " + e;
		}

		// Close everything
		if (producer != null) {
			try {
				producer.close();
			} catch (Exception e) {
				result = "Error closing ActiveMQ producer" + sequence
						+ " Error message: " + e.getMessage();
			}
		}
		if (session != null) {
			try {
				session.close();
			} catch (Exception e) {
				result = "Error closing ActiveMQ session" + sequence
						+ " Error message: " + e.getMessage();
			}
		}

		if (result.equals(""))
			result = "OK";

		return result;
	}

	private static void printUsage(Options options) {

		System.out.println();

		HelpFormatter formatter = new HelpFormatter();
		formatter.printHelp(ConsumerMain.class.getSimpleName(), options, true);
	}

	public static void main(String[] args) {

		String brokerURL;
		String username;
		String password;
		ActiveMQConnectionFactory connectionFactory;

		Options options = new Options();
		options.addOption("all", false, "Sync all grouper groups");
		options.addOption("group", true, "Grouper group to sync");
		options.addOption("priv", false, "Grouper group for which privileges to sync");
		options.addOption("allpriv", false, "Sync all grouper groups privileges");
		options.addOption("usdu", false, "Run USDU on all subject source");

		if (args.length == 0) {
			printUsage(options);
			System.exit(0);
		}

		CommandLineParser parser = new GnuParser();
		CommandLine line = null;

		try {
			line = parser.parse(options, args);
		} catch (ParseException e) {
			System.err.println(e.getMessage());
			printUsage(options);
			System.exit(1);
		}

		brokerURL = ConsumerProperties.getBrokerUrl();
		username = ConsumerProperties.getUsername();
		password = ConsumerProperties.getPassword();

		try {
			// Create a Connection Factory and connection
			connectionFactory = new ActiveMQConnectionFactory(username,
					password, brokerURL);
			connection = connectionFactory.createConnection();
			connection.start();
		} catch (Exception e) {
			LOG.error("Error connecting to ActiveMQ ", e);
			System.exit(1);
		}

		try {
			GrouperSession session = GrouperSession.start(SubjectFinder
					.findRootSubject());

			if (line.hasOption("all")) {
				syncAllGroups(session);
			} else if (line.hasOption("allpriv")) {
				syncAllPrivs(session);
			} else if (line.hasOption("group")) {
				if (line.hasOption("priv")) {
					syncPriv(session, line.getOptionValue("group"));
				}else{
					syncGroup(session, line.getOptionValue("group"));
				}
			} else if (line.hasOption("usdu")) {
				try {
					USDUWrapper.resolveMembers(session);
				} catch (Exception e) {
					LOG.error("Error running USDU ", e);
					System.exit(0);
				}

			} else {
				printUsage(options);
				System.exit(0);
			}

		} catch (Exception e) {
			System.err.println(e.getMessage());
			System.exit(1);
		}

		if (connection != null) {
			try {
				connection.close();
			} catch (Exception e) {
				LOG.error("Error closing ActiveMQ connection", e);
			}
		}

	}

	private static void syncAllGroups(GrouperSession session) {
		LOG.debug("In syncAllGroups");
		//Set<Group> groups = GroupFinder.findAllByType(session,
		//		GroupTypeFinder.find("base", false));
		//Set<Group> groups = GroupFinder.findGroups();
		Stem stem = StemFinder.findByName(session, "edu:berkeley");
		Set<Group> groups = stem.getChildGroups(Scope.SUB);

		LOG.debug("Here is the group list: " + groups);

		for (Group group : groups) {
			LOG.debug("Full sync group: " + group.getName());
			Set<Member> members = getAllGroupMembers(group, session);

			String mesg = getGroupFullSyncMessage(group, members);
			String mesgIsMemberOf = getIsMemberOfFullSyncMessage(group, members);
			LOG.debug(mesg);
			LOG.debug(mesgIsMemberOf);

			try {
				writeMessage(mesg, group.getName(), 0);
				writeMessage(mesgIsMemberOf, group.getName(), 0);
			} catch (Exception e) {
				LOG.error("Error sending activemq message ", e);
			}
			LOG.info("Full Sync completed sucessfully for group: "
					+ group.getName());
		}
	}

	private static void syncAllPrivs(GrouperSession session) {
		Set<Group> groups = GroupFinder.findAllByType(session,
				GroupTypeFinder.find("base", false));

		for (Group group : groups) {
			LOG.debug("Full sync privilege for group: " + group.getName());
			Set<Subject> subjects = group.getAdmins();
			subjects.addAll(group.getUpdaters());
			String mesg = getGroupPrivilegeFullSyncMessage(group, subjects);
			LOG.debug(mesg);
			try {
				writeMessage(mesg, group.getName(), 0);
			} catch (Exception e) {
				LOG.error("Error sending activemq message ", e);
			}
			LOG.info("Full Sync privilege completed sucessfully for group: "
					+ group.getName());
		}
	}

	private static void syncGroup(GrouperSession session, String groupName) {
		Group group = GroupFinder.findByName(session, groupName, false);
		if (group != null) {
			LOG.debug("Sync for group: " + group.getName());
			Set<Member> members = getAllGroupMembers(group, session);

			String mesg = getGroupFullSyncMessage(group, members);
			String mesgIsMemberOf = getIsMemberOfFullSyncMessage(group, members);
			LOG.debug(mesg);
			LOG.debug(mesgIsMemberOf);
			try {
				writeMessage(mesg, group.getName(), 0);
				writeMessage(mesgIsMemberOf, group.getName(), 0);
			} catch (Exception e) {
				LOG.error("Error sending activemq message ", e);
			}

			LOG.info("Full Sync completed sucessfully for group "
					+ group.getName());

		} else {
			LOG.debug("Group not found " + groupName);
		}
	}
	
	private static void syncPriv(GrouperSession session, String groupName) {
		Group group = GroupFinder.findByName(session, groupName, false);
		if (group != null) {
			LOG.debug("Full sync privilege for group : " + group.getName());
			
			Set<Subject> subjects = group.getAdmins();
			subjects.addAll(group.getUpdaters());
			String mesg = getGroupPrivilegeFullSyncMessage(group, subjects);
			LOG.debug(mesg);
			try {
				writeMessage(mesg, group.getName(), 0);
			} catch (Exception e) {
				LOG.error("Error sending activemq message ", e);
			}

			LOG.info("Full Sync privilege completed sucessfully for group "
					+ group.getName());

		} else {
			LOG.debug("Group not found " + groupName);
		}
	}

}
