/*Copyright 2014 Carnegie Mellon University
All rights reserved.

Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

1. Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.

2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.

3. Neither the name of the copyright holder nor the names of its contributors may be used to endorse or promote products derived from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.*/

package edu.cmu.grouper.changelog.consumer;

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

/**
 * Class to dispatch individual events
 */
public class ConsumerMain extends ChangeLogConsumerBase {

	private static final Log LOG = LogFactory
			.getLog(edu.cmu.grouper.changelog.consumer.ConsumerMain.class);
	private GrouperSession gs;
	private ActiveMQConnectionFactory connectionFactory;
	private static Connection connection;

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

		brokerURL = ConsumerProperties.getBrokerUrl();
		username = ConsumerProperties.getUsername();
		password = ConsumerProperties.getPassword();
		long currentId = 0;

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
			// read and check properties
			if (!ConsumerProperties.propertiesOk()) {
				LOG.error("Couldn't process any records: Error"
						+ " reading properties file " + currentId);
				return currentId - 1;
			}

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
						String mesg = getGroupAddedMessage(groupName);
						writeMessage(mesg, groupName, currentId);
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
						String propertyChanged = changeLogEntry
								.retrieveValueForLabel(ChangeLogLabels.GROUP_UPDATE.propertyChanged);
						if (propertyChanged.equals("description")) {
							String groupOldDescription = changeLogEntry
									.retrieveValueForLabel(ChangeLogLabels.GROUP_UPDATE.propertyOldValue);
							if (groupOldDescription == null) {
								groupOldDescription = "";
							}
							getGroupUpdatedMessage(groupName, groupDescription,
									groupOldDescription);
						} else if (propertyChanged.equals("name")) {
							String groupOldName = changeLogEntry
									.retrieveValueForLabel(ChangeLogLabels.GROUP_UPDATE.propertyOldValue);
							String mesg = getGroupRenamedMessage(groupName,
									groupOldName);
							writeMessage(mesg, groupName, currentId);
						} else {
							LOG.debug("Skipping sequence "
									+ changeLogEntry.getSequenceNumber()
									+ " as group update property: "
									+ propertyChanged + " is not handled");
						}

					}
				} else if (changeLogEntry
						.equalsCategoryAndAction(ChangeLogTypeBuiltin.GROUP_DELETE)) {
					groupName = changeLogEntry
							.retrieveValueForLabel(ChangeLogLabels.GROUP_DELETE.name);
					if (groupName == null) {
						LOG.error("No group name for group delete change type. Skipping sequence: "
								+ currentId);
					} else {
						String mesg = getGroupDeletedMessage(groupName);
						String mesgIsMemberOf = getGroupDeletedIsMemberOfMessage(groupName);
						writeMessage(mesg, groupName, currentId);
						writeMessage(mesgIsMemberOf, groupName, currentId);
					}
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
						if (member != null) {
							String memberName = null;

							if (member.getSubjectType().toString()
									.equals("person")) {
								memberName = member.getSubjectId();
								String mesgIsMemberOf = getIsMemberOfAddedMessage(
										groupName, memberName);
								writeMessage(mesgIsMemberOf, groupName,
										currentId);
							} else {
								memberName = member.getName();
							}

							String mesg = getGroupMemberAddedMessage(groupName,
									memberName);
							writeMessage(mesg, groupName, currentId);
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
						if (member != null) {
							String memberName = null;

							if (member.getSubjectType().toString()
									.equals("person")) {
								memberName = member.getSubjectId();
								String mesgIsMemberOf = getIsMemberOfDeletedMessage(
										groupName, memberName);
								writeMessage(mesgIsMemberOf, groupName,
										currentId);
							} else {
								memberName = member.getName();
							}
							String mesg = getGroupMemberDeletedMessage(
									groupName, memberName);
							writeMessage(mesg, groupName, currentId);
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
						if (member != null) {
							String memberName = null;

							if (member.getSubjectType().toString()
									.equals("person")) {
								memberName = member.getSubjectId();
								String mesgPrivilegeAdd = getPrivilegeAddedMessage(
										groupName, memberName);
								writeMessage(mesgPrivilegeAdd, groupName,
										currentId);
							} else {
								memberName = member.getName();
							}
							String mesg = getPrivilegeAddedMessage(groupName,
									memberName);
							writeMessage(mesg, groupName, currentId);
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
						if (member != null) {
							String memberName = null;

							if (member.getSubjectType().toString()
									.equals("person")) {
								memberName = member.getSubjectId();
								String mesgPrivilegeDelete = getPrivilegeDeletedMessage(
										groupName, memberName);
								writeMessage(mesgPrivilegeDelete, groupName,
										currentId);
							} else {
								memberName = member.getName();
							}
							String mesg = getPrivilegeDeletedMessage(groupName,
									memberName);
							writeMessage(mesg, groupName, currentId);
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

	private String getGroupAddedMessage(String groupName) {
		String mesg = "<operation>createGroup</operation>";
		mesg = mesg + "<name><![CDATA[" + groupName + "]]></name>";
		return mesg;
	}

	private String getGroupDeletedMessage(String groupName) {
		String mesg = "<operation>deleteGroup</operation>";
		mesg = mesg + "<name><![CDATA[" + groupName + "]]></name>";
		return mesg;
	}

	private String getGroupDeletedIsMemberOfMessage(String groupName) {
		String mesg = "<operation>deleteGroupIsMemberOf</operation>";
		mesg = mesg + "<name><![CDATA[" + groupName + "]]></name>";
		return mesg;
	}

	private String getGroupUpdatedMessage(String groupName,
			String groupDescription, String groupOldDescription) {
		String mesg = "<operation>updateGroup</operation>";
		mesg = mesg + "<name><![CDATA[" + groupName + "]]></name>";
		mesg = mesg + "<description><![CDATA[" + groupDescription
				+ "]]></description>";
		mesg = mesg + "<olddescription><![CDATA[" + groupOldDescription
				+ "]]></olddescription>";
		return mesg;
	}

	private String getGroupRenamedMessage(String groupName, String groupOldName) {
		String mesg = "<operation>renameGroup</operation>";
		mesg = mesg + "<name><![CDATA[" + groupName + "]]></name>";
		mesg = mesg + "<oldname><![CDATA[" + groupOldName + "]]></oldname>";
		return mesg;
	}

	private String getGroupMemberAddedMessage(String groupName, String uid) {
		String mesg = "<operation>addMember</operation>";
		mesg = mesg + "<name><![CDATA[" + groupName + "]]></name>";
		mesg = mesg + "<memberId><![CDATA[" + uid + "]]></memberId>";
		return mesg;
	}

	private String getIsMemberOfAddedMessage(String groupName, String uid) {
		String mesg = "<operation>addIsMemberOf</operation>";
		mesg = mesg + "<name><![CDATA[" + groupName + "]]></name>";
		mesg = mesg + "<memberId><![CDATA[" + uid + "]]></memberId>";
		return mesg;
	}

	private String getGroupMemberDeletedMessage(String groupName, String uid) {
		String mesg = "<operation>removeMember</operation>";
		mesg = mesg + "<name><![CDATA[" + groupName + "]]></name>";
		mesg = mesg + "<memberId><![CDATA[" + uid + "]]></memberId>";
		return mesg;
	}

	private String getIsMemberOfDeletedMessage(String groupName, String uid) {
		String mesg = "<operation>removeIsMemberOf</operation>";
		mesg = mesg + "<name><![CDATA[" + groupName + "]]></name>";
		mesg = mesg + "<memberId><![CDATA[" + uid + "]]></memberId>";
		return mesg;
	}

	private String getPrivilegeAddedMessage(String groupName, String uid) {
		String mesg = "<operation>addPrivilege</operation>";
		mesg = mesg + "<name><![CDATA[" + groupName + "]]></name>";
		mesg = mesg + "<memberId><![CDATA[" + uid + "]]></memberId>";
		return mesg;
	}

	private String getPrivilegeDeletedMessage(String groupName, String uid) {
		String mesg = "<operation>removePrivilege</operation>";
		mesg = mesg + "<name><![CDATA[" + groupName + "]]></name>";
		mesg = mesg + "<memberId><![CDATA[" + uid + "]]></memberId>";
		return mesg;
	}

	private static String getGroupFullSyncMessage(Group group,
			Set<Member> members) {
		String mesg = "<operation>fullSync</operation>";
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
		return mesg;
	}

	private static String getGroupPrivilegeFullSyncMessage(Group group,
			Set<Subject> subjects) {
		String mesg = "<operation>fullSyncPrivilege</operation>";
		mesg = mesg + "<description><![CDATA[" + group.getDescription()
				+ "]]></description>";
		mesg = mesg + "<name><![CDATA[" + group.getName() + "]]></name>";
		mesg = mesg + "<memberList>";

		for (Subject subject : subjects) {
				if (subject.getSourceId().equals("ldap")){
					mesg = mesg + "<member><![CDATA[" + subject.getId()
								+ "]]></member>";
				}else{
					mesg = mesg + "<member><![CDATA[" + subject.getName()
							+ "]]></member>";
				}
		}

		mesg = mesg + "</memberList>";
		return mesg;
	}

	private static String getIsMemberOfFullSyncMessage(Group group,
			Set<Member> members) {
		String mesg = "<operation>fullSyncIsMemberOf</operation>";
		mesg = mesg + "<name><![CDATA[" + group.getName() + "]]></name>";
		mesg = mesg + "<memberList>";

		for (Member member : members) {
			if (member.getSubjectType().toString().equals("person")) {
				mesg = mesg + "<member><![CDATA[" + member.getSubjectId()
						+ "]]></member>";
			}
		}

		mesg = mesg + "</memberList>";
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

		if (!ConsumerProperties.propertiesOk()) {
			return "Required properties not available";
		}

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
		Set<Group> groups = GroupFinder.findAllByType(session,
				GroupTypeFinder.find("base", false));

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
