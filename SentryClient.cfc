<cfimport path="lib.utils.patterns" />
<cfcomponent accessors="true">
  <cfproperty name="matcher" />
  <cfproperty name="protocol" />
  <cfproperty name="PublicKey" />
  <cfproperty name="PrivateKey" />
  <cfproperty name="Host" />
  <cfproperty name="ProjectID" />
  <cfproperty name="EndPoint" />
  <cfproperty name="ColdfusionStackRegex" />
  <cfproperty name="ShowJavaStackTrace" />
  <cfproperty name="Tags" default="{}" />
  <cffunction name="init">
    <cfargument name="DSN" required="true" />
    <cfargument name="ShowJavaStackTrace" default="false" />
    <cfargument name="Tags" default="{}" />
    <cfset VARIABLES.ShowJavaStackTrace = ARGUMENTS.ShowJavaStackTrace />
    <cfset VARIABLES.Tags = ARGUMENTS.Tags />
    <cfset ProcessDSN(ARGUMENTS.DSN) />
  </cffunction>
  
  <cffunction name="ProcessDSN">
    <cfargument name="DSN" required="true" />
    <cfset VARIABLES.matcher = new lib.Utils.Patterns.Regex(
		  "(https?):\/\/(.*):(.*)@(.*)\/(.*)",
      ARGUMENTS.DSN
    ) />
    
    <cfif !VARIABLES.Matcher.Find() >
      <cfthrow message="DSN Did not follow the correct format" />
    </cfif>
    <cfset local.Groups = VARIABLES.Matcher.Groups() >
    <cfset VARIABLES.ColdfusionStackRegex = "at ([\w\d\.\_\$]+)\(([\w\d\.\_\/]+):([\d]+)\)" />
    <cfset VARIABLES.protocol = local.Groups[2] />
    <cfset VARIABLES.PublicKey = local.Groups[3] />
    <cfset VARIABLES.PrivateKey = local.Groups[4] />
    <cfset VARIABLES.Host = local.Groups[5] />
    <cfset VARIABLES.ProjectID = local.Groups[6] />
    <cfset VARIABLES.EndPoint = "#VARIABLES.Protocol#://#VARIABLES.Host#/api/#VARIABLES.ProjectID#/store/" />
  </cffunction>

  <cffunction name="getCookies">
    <cfargument name="request"/>
    <cfset out = [] />
    <cfset local.cookies = COOKIE />
    <cfloop collection="#local.cookies#" item="cooks">
      
      <cfset local.cookieName = cooks />
      <cfset ArrayAppend(out,"#local.cookieName#=#local.cookies[local.cookieName]#") />
    </cfloop>
    <cfreturn ArrayToList(out,'; ') />
  </cffunction>

  <cffunction name="getQueryParams">
    <cfargument name="request">
    <cfset local.queryString = ARGUMENTS.request.getQueryString() />
    <cfif IsNull(local.queryString) >
      <cfreturn "" />
    </cfif>
    <cfreturn local.queryString />
  </cffunction>

  <cffunction name="getHeaders">
    <cfargument name="request">
    <cfreturn GetHttpRequestData().headers />
  </cffunction>

  <cffunction name="buildBasePayload">
    <cfargument name="culprit" />
    <cfargument name="message" />
    <cfset datetime = dateConvert( "local2utc", now() ) />
    <cfset formattedDate = dateFormat( datetime, "yyyy-mm-dd" ) &
      "T" &
      timeFormat( datetime, "HH:mm:ss" ) &
      "Z" />
      <cfset local.Request = getPageContext().GetRequest() />
      <cfset local.queryString = local.request.getQueryString() />
      <cfset local.URL = local.request.getRequestURL().ToString() />
      <cfset local.Method = local.request.getMethod() />
      <cfset local.SentryException = {
      "event_id" = lcase(replace(createUUID(), '-', '', 'all')),
      "culprit" = ARGUMENTS.culprit,
      "message" = ARGUMENTS.message,
      "timestamp" = formattedDate,
      "exception" = [],
      "platform" = 'cfml',
      "logger" = "cf-raven/1.0.0",
      "request" = {
        "url" = local.URL,
        "method" = local.method,
        "query_string" = getQueryParams(local.request),
        "cookies" = getCookies(local.Request),
        "headers" = getHeaders(local.Request),
        "data" = FORM
      },
      "tags" = VARIABLES.Tags
    } />
    <cfreturn local.sentryException />
  </cffunction>

  <cffunction name="captureException">
    <cfargument name="exception">
    <cfargument name="eventName">
    <cfset local.Cause = exception.Cause />
    <cfset datetime = dateConvert( "local2utc", now() ) />
    <cfset local.sentryException = buildBasePayload(ARGUMENTS.eventname, local.Cause.message) />
    <cfset ArrayAppend(local.SentryException.exception,buildException(local.Cause)) />
    <cfif StructKeyExists(VARIABLES,'ShowJavaStackTrace') AND VARIABLES.ShowJavaStackTrace eq true>
        <cfset local.sentryException['extra'] = {
            "JavaStackTrace" = this.buildJavaStackTrace(exception.StackTrace)
        } />
    </cfif>
    <cfset logEvent(local.sentryException) />
  </cffunction>

  <cffunction name="GetAuthHeaderValue">
    <cfargument name="timestamp" />
    <cfset local.value = "Sentry " 
      & "sentry_version=5,"
      & "sentry_client=cf_raven/1.0.0"
      & "sentry_timestamp=#ARGUMENTS.timestamp#,"
      & "sentry_key=#PublicKey#,"
      & "sentry_secret=#PrivateKey#"
    />
    <cfreturn local.value />
  </cffunction>

  <cffunction name="logEvent">
    <cfargument name="payload" />
    <cfset local.contentBody="#SerializeJSON(payload)#" />
    <cfset local.AuthHeader = GetAuthHeaderValue(payload.timestamp) />
    <cfhttp url="#VARIABLES.EndPoint#" method="POST"  result="local.result"> 
      <cfhttpparam 
        type="header" 
        name="X-Sentry-Auth" 
        value="#local.AuthHeader#" />
      <cfhttpparam
        type="header"
        name="Content-Type"
        value="application/json"
      />
      <cfhttpparam 
        type="body"
        value="#contentBody#"
      >
    </cfhttp>
    <cfif result.statuscode neq "200 OK" >
      <cflog type="error" 
        file="SentryClient" 
        log="Application" 
        text="Sentry could not log error: #result.errorDetail# - #result.fileContent#" 
        application="yes" />
    </cfif>
  </cffunction>

  <cffunction name="buildException">
    <cfargument name="exception" />
    <cfset local.output = {
      "type" = exception.type,
      "value" = exception.detail,
      "stacktrace" = {
        "frames" = []
      }
    } />
    <cfset local.output['stacktrace']['frames'] = this.buildTagStackTrace(exception.TagContext) />
    <cfreturn local.output />
  </cffunction>

  <cffunction name="buildTagStackTrace">
    <cfargument name="TagContext">
    <cfset tagLines = [] />    
    <cfloop array="#TagContext#" index="tagLine">
      <cfset local.line = {
        "lineno" = tagLine.Line,
        "colno" = tagLine.column,
        "filename" = tagLine.template
      } />
    <cfset local.contextLine = getStackContext(tagLine.template, tagLine.Line) >
    <cfset local.line['context_line'] = local.contextLine.context />
    <cfset local.line['pre_context'] = local.contextLine.pre_context />
    <cfset local.line['post_context'] = local.contextLine.post_context />
    <cfset ArrayPrepend(tagLines,local.line) />
    </cfloop>
    <cfreturn tagLines />
  </cffunction>

  <cffunction name="getStackContext">
    <cfargument name="filename" />
    <cfargument name="line" />
    <cfset local.context = {
      'pre_context' = [],
      'context' = "",
      'post_context' = []
    } />

    <cfset contextLines = 5 />
    <cfif fileExists(filename) >
      <cfset fileHandle = FileOpen(filename, "Read") >
      <cfset lineNo = 1 />
      <cfloop condition="NOT FileIsEOF(fileHandle) AND lineNo LTE ARGUMENTS.Line + contextLines">
        <cfset local.currentLine = FileReadLine(fileHandle) />
        <cfif lineNo eq ARGUMENTS.line >
          <cfset local.context['context'] = local.currentLine />
        <cfelseif lineNo GTE line - contextLines AND lineNo LT ARGUMENTS.line>
          <cfset arrayAppend(local.context['pre_context'], currentLine) />
        <cfelseif lineNo LTE line + contextLines AND lineNo GT ARGUMENTS.line>
          <cfset arrayAppend(local.context['post_context'], currentLine) />
        </cfif>
        <cfset lineNo += 1 />
      </cfloop>
      <cfset FileClose(fileHandle) />
    </cfif>
    <cfreturn local.context />
  </cffunction>

  <cffunction name="buildJavaStackTrace">
    <cfargument name="StackTrace" />
    <cfset local.stackList = REMatch(VARIABLES.ColdfusionStackRegex, ARGUMENTS.StackTrace) />
    <cfset local.output = [] />
    <cfloop array="#local.stackList#" index="index">
      <cfset ArrayAppend(local.output, buildStackFrame(index)) />
    </cfloop>
    <cfreturn local.output />
  </cffunction>

  <cffunction name="buildStackFrame">
    <cfargument name="stackLine">
      <cfset local.lineMatcher = new lib.Utils.Patterns.Regex(
		    VARIABLES.ColdfusionStackRegex,
        ARGUMENTS.StackLine
      ) />
      <cfif !local.lineMatcher.Find() >
        <cfreturn {} />
      </cfif>
      <cfset local.Groups  = local.lineMatcher.Groups() />
      <cfset local.line = {
          "lineno" = local.Groups[4],
          "filename" = local.Groups[3],
          "module" = local.Groups[2]
      } />
      <cfreturn local.line />
  </cffunction>
</cfcomponent>