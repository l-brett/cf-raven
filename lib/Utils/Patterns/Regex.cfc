<cfcomponent>
  <cfproperty name="Matches">
  <cfproperty name="FoundGroups" >
  <cfproperty name="HasMatch" default="null" />
  <cffunction name="init">
    <cfargument name="pattern">
    <cfargument name="stringToMatch">
    <cfset VARIABLES.FoundGroups = [] />
    <cfset VARIABLES.matcher = CreateObject("java", "java.util.regex.Pattern")
	  .Compile(JavaCast("string",pattern)) />
    <cfset VARIABLES.matches = VARIABLES.matcher.Matcher(stringToMatch) />
  </cffunction>
  
  <cffunction name="Find">
    <cfif !IsNull(VARIABLES.HasMatch) >
      <cfreturn VARIABLES.HasMatch />
    </cfif>
    <cfset VARIABLES.hasMatch = VARIABLES.matches.Find() />
    <cfreturn VARIABLES.hasMatch  />
  </cffunction>

  <cffunction name="Groups">
    <cfif !ArrayIsEmpty(VARIABLES.FoundGroups) >
      <creturn VARIABLES.FoundGroups >
    </cfif>
    <cfset VARIABLES.FoundGroups = [] />
    <cfloop index="index" from="0" to="#VARIABLES.matches.groupCount()#">
      <cfset ArrayAppend(
        VARIABLES.FoundGroups,
        VARIABLES.matches.Group(
          javacast("int",
            index
          )
        )
      ) />
    </cfloop>

    <cfreturn VARIABLES.FoundGroups />
  </cffunction>
</cfcomponent>
