/*=============================================================================
USE CASE 3: HR POLICY SUPPORT AGENT — Enterprise Knowledge Assistant

Enterprise Value: A single conversational agent that helps employees find
answers from HR policy documents in plain English. Employees can ask about
leave policies, compliance training, flexible benefits, payroll, investment
declaration, IT support contacts, and onboarding requirements without
manually searching through multiple documents.

The agent uses Cortex Search to retrieve the most relevant information from
HR policy documents and provides a clear, grounded response.

Components:
- CREATE CORTEX SEARCH SERVICE on HR policy and FAQ documents
- CREATE AGENT with cortex_search tool
- Conversational HR support demonstrated via DATA_AGENT_RUN
=============================================================================*/

USE DATABASE HR_POLICIES_DB;
USE SCHEMA HR_POLICIES_DB.DEV;
USE WAREHOUSE CORTEX_DEMO_WH;

CREATE OR REPLACE AGENT HR_POLICIES_DB.DEV.HR_POLICY_AGENT2
  FROM SPECIFICATION $$
models:
  orchestration: auto
instructions:
  orchestration: >
    You are an HR Policy Support Assistant for employees.

    Answer questions only using the information retrieved from the
    POLICY_SEARCH tool. The available documents cover only:

    - Annual health check-up policy
    - Leave policy
    - Notice period policy
    - Office timing and attendance policy
    - Separation policy
    - Travel policy

    Use POLICY_SEARCH for every question.

    Do not answer questions about topics not covered in these documents, such as
    payroll, flexible pay, investment declaration, compliance training,
    onboarding, benefits, IT access, reimbursements, or other HR policies.

    If the requested information is not available in the retrieved content,
    respond clearly that it is not covered in the currently available HR policy
    documents. Suggest contacting the HR team for further clarification.

  response: >
    Be helpful, simple, and concise.

    Answer only from the retrieved policy content. Clearly mention important
    timelines, eligibility conditions, employee actions, approvals, and
    exceptions when they are available in the documents.

    Do not assume, infer, or invent policy details. Mention the relevant policy
    document name in every answer.

tools:
  - tool_spec:
      type: cortex_search
      name: POLICY_SEARCH
      description: >
        Searches approved HR policy documents covering annual health check-ups,
        leave, notice periods, office timings, separation, and business travel.
        Use for every employee question about these topics.

tool_resources:
  POLICY_SEARCH:
    name: HR_POLICIES_DB.DEV.POLICY_SEARCH
    max_results: 5
$$;

-- Verify
SHOW AGENTS IN SCHEMA HR_POLICIES_DB.DEV;



/*-----------------------------------------------------------------------------
  Testing non existent information questions with Agent
-----------------------------------------------------------------------------*/

--This detail doesnt exist in any document so it should not return any policy details and ask to reach out to HR team.
WITH RESP AS (
  SELECT TRY_PARSE_JSON(SNOWFLAKE.CORTEX.DATA_AGENT_RUN(
    'HR_POLICIES_DB.DEV.HR_POLICY_AGENT',
    $${ "messages": [{"role": "user", "content": [{"type": "text", "text": "What is our remote work policy? How many days do I need to be in office?"}]}] }$$,
    TRUE)) AS R
)
SELECT f.value:text::STRING AS ANSWER FROM RESP, LATERAL FLATTEN(input => R:content) f WHERE f.value:type = 'text';

/*-----------------------------------------------------------------------------
  Testing relevant questions with Agent
-----------------------------------------------------------------------------*/

WITH RESP AS (
  SELECT TRY_PARSE_JSON(SNOWFLAKE.CORTEX.DATA_AGENT_RUN(
    'HR_POLICIES_DB.DEV.HR_POLICY_AGENT',
    $${ "messages": [{"role": "user", "content": [{"type": "text", "text": "What all travel expense are covered for Europe and how much?"}]}] }$$,
    TRUE)) AS R
)
SELECT f.value:text::STRING AS ANSWER FROM RESP, LATERAL FLATTEN(input => R:content) f WHERE f.value:type = 'text';


/*-----------------------------------------------------------------------------
  Testing questions which need reference to multiple pdfs at once.
-----------------------------------------------------------------------------*/

WITH RESP AS (
  SELECT TRY_PARSE_JSON(SNOWFLAKE.CORTEX.DATA_AGENT_RUN(
    'HR_POLICIES_DB.DEV.HR_POLICY_AGENT',
    $${ "messages": [{"role": "user", "content": [{"type": "text", "text": "What is the leave policy for employees during the notice period??"}]}] }$$,
    TRUE)) AS R
)
SELECT f.value:text::STRING AS ANSWER FROM RESP, LATERAL FLATTEN(input => R:content) f WHERE f.value:type = 'text';

CREATE OR REPLACE MCP SERVER hrpolicy_mcp_server
    FROM SPECIFICATION $$
    tools:
      - name: "HR-Policy-Details"
        type: "CORTEX_AGENT_RUN"
        identifier: "HR_POLICIES_DB.DEV.HR_POLICY_AGENT"
        description: "HR Policy Agent is your virtual HR assistant, designed to answer questions about company policies and workplace guidelines. Whether you need information about leave, benefits, work hours, reimbursements, or employee programs, the agent provides fast, reliable, and easy-to-understand responses based on approved HR policies."
        title: "HR Policy Agent"
    $$;

    SELECT SYSTEM$SHOW_OAUTH_CLIENT_SECRETS('SF_MCP_OAUTH3');
    SELECT PARSE_JSON(SYSTEM$SHOW_OAUTH_CLIENT_SECRETS('SF_MCP_OAUTH')):OAUTH_CLIENT_SECRET::string AS my_secret;

    show MCP SERVERS;

    SELECT PARSE_JSON(SYSTEM$SHOW_OAUTH_CLIENT_SECRETS('SF_MCP_OAUTH'))
         :OAUTH_CLIENT_ID::string     AS client_id,
       PARSE_JSON(SYSTEM$SHOW_OAUTH_CLIENT_SECRETS('SF_MCP_OAUTH'))
         :OAUTH_CLIENT_SECRET::string AS client_secret;

DESCRIBE SECURITY INTEGRATION sf_mcp_oauth3;

CREATE or replace SECURITY INTEGRATION sf_mcp_oauth
  TYPE = OAUTH
  OAUTH_CLIENT = CUSTOM
  ENABLED = TRUE
  OAUTH_CLIENT_TYPE = 'CONFIDENTIAL'
  OAUTH_ISSUE_REFRESH_TOKENS = TRUE
  OAUTH_REFRESH_TOKEN_VALIDITY = 86400
  OAUTH_USE_SECONDARY_ROLES = IMPLICIT
  OAUTH_REDIRECT_URI = 'https://localhost';

  ALTER SECURITY INTEGRATION sf_mcp_oauth
  SET OAUTH_REDIRECT_URI = 'https://global.consent.azure-apim.net/redirect/cr157-5fhrpolicy-5fmcp-5fserver2-5f22a3db184ffa322c';

  desc INTEGRATION sf_mcp_oauth;