/*Copyright 2014 Carnegie Mellon University
All rights reserved.

Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

1. Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.

2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.

3. Neither the name of the copyright holder nor the names of its contributors may be used to endorse or promote products derived from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.*/

package edu.cmu.grouper.changelog.consumer;

import java.lang.Exception;
import java.net.URL;
import java.util.Properties;

//import edu.internet2.middleware.grouperClient.config.ConfigPropertiesCascadeBase;
import edu.internet2.middleware.grouper.app.loader.GrouperLoaderConfig;


import org.slf4j.Logger;
import org.slf4j.LoggerFactory;


/**
 * Act on member changes
 */
public class ConsumerProperties {

	private static final Logger LOG = LoggerFactory.getLogger(edu.cmu.grouper.changelog.consumer.ConsumerMain.class);
	
	//private final static Log log = LogFactory.getLog(edu.cmu.grouper.changelog.consumer.ConsumerMain.class);
	private static final String PARAMETER_NAMESPACE = "changeLog.consumer.";
	
	private static String brokerURL = null;
	private static String username = null;
	private static String password = null;
	private static String targets = null;
	private static String usduExcludes = null;
	private static String allowLargeGroupsAttribute = null;
	private static int maxMembers = 0;
	private static String syncAttribute = null;
	private static String syncType = null;
	private static boolean useXmlMessageFormat = false;

	public ConsumerProperties(String consumerName) {
		
		final String qualifiedParameterNamespace = PARAMETER_NAMESPACE + consumerName + ".";

	    LOG.debug("CMU Consumer - Setting properties for {} consumer/provisioner.", consumerName);


		try {
			
			brokerURL = 
					GrouperLoaderConfig.retrieveConfig().propertyValueStringRequired(qualifiedParameterNamespace + "brokerURL");
					LOG.debug("CMU Consumer - Setting brokerURL to {}", brokerURL);
			        
			username = 
					GrouperLoaderConfig.retrieveConfig().propertyValueStringRequired(qualifiedParameterNamespace + "username");
					LOG.debug("CMU Consumer - Setting username to {}", username);
			        
			password = 
					GrouperLoaderConfig.retrieveConfig().propertyValueString(qualifiedParameterNamespace + "password", "");
					LOG.debug("CMU Consumer - Setting password to {}", password);
			
			targets = 
					GrouperLoaderConfig.retrieveConfig().propertyValueStringRequired(qualifiedParameterNamespace + "targets");
					LOG.debug("CMU Consumer - Setting targets to {}", targets);
			   
			usduExcludes = 
					GrouperLoaderConfig.retrieveConfig().propertyValueString(qualifiedParameterNamespace + "usduExcludes", "");
					LOG.debug("CMU Consumer - Setting usduExcludes to {}", usduExcludes);
			
			allowLargeGroupsAttribute = 
					GrouperLoaderConfig.retrieveConfig().propertyValueString(qualifiedParameterNamespace + "allowLargeGroupsAttribute", "");
					LOG.debug("CMU Consumer - Setting allowLargeGroupsAttribute to {}", allowLargeGroupsAttribute);
			
			maxMembers = 
					GrouperLoaderConfig.retrieveConfig().propertyValueInt(qualifiedParameterNamespace + "maxMembers", 1000);
					LOG.debug("CMU Consumer - Setting maxMembers to {}", maxMembers);
			
			syncAttribute = 
					GrouperLoaderConfig.retrieveConfig().propertyValueStringRequired(qualifiedParameterNamespace + "syncAttribute");
					LOG.debug("CMU Consumer - Setting syncAttribute to {}", syncAttribute);
			   		
			syncType = 
					GrouperLoaderConfig.retrieveConfig().propertyValueString(qualifiedParameterNamespace + "syncType", "basic");
					LOG.debug("CMU Consumer - Setting syncType to {}", syncType);
					
			useXmlMessageFormat = 
					GrouperLoaderConfig.retrieveConfig().propertyValueBoolean(qualifiedParameterNamespace + "useXmlMessageFormat", true);
					LOG.debug("CMU Consumer - Setting useXmlMessageFormat to {}", useXmlMessageFormat);
		
			   				

		} catch (Exception e) {
			LOG.error("Error reading configuration values: " + e);
		}
	}

	
	public static String getBrokerUrl() {
		return brokerURL;
	}

	public static String getUsername() {
		return username;
	}

	public static String getPassword() {
		return password;
	}
	
	public static String getTargets() {
		return targets;
	}
	
	public static String getUsduExcludes() {
		return usduExcludes;
	}
	
	public static String getAllowLargeGroupsAttribute() {
		       return allowLargeGroupsAttribute;
	}
	

	public static int getMaxMembers() {
		return maxMembers;
	}

	public static String getSyncAttribute() {
		return syncAttribute;
	}
	
	public static String getSyncType() {
		return syncType;
	}
	
	public static boolean getUseXmlMessageFormat() {
		return useXmlMessageFormat;
	}
	

	
}
