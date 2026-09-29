/*=============================================================================
CORTEX SEARCH SERVICE — Enterprise Document Search
  
  Enterprise Value: Employees can search company documents in plain English
  and instantly find relevant policy details, FAQs, guides, and procedures.
  No need to manually open and read multiple documents.
  
  Components:
    - DOCUMENT TABLE: Store document text, metadata, category, and source link
    - CREATE CORTEX SEARCH SERVICE: Build semantic search over document content
    - SEARCH_PREVIEW: Test search results directly in Snowflake
    - STREAMLIT / AGENT: Build a chat interface for employees
=============================================================================*/

USE DATABASE HR_POLICIES_DB;
USE SCHEMA HR_POLICIES_DB.DEV;
USE WAREHOUSE CORTEX_DEMO_WH;


/*-----------------------------------------------------------------------------
  STEP 1: CREATE CORTEX SEARCH SERVICE — Index the knowledge base
  
  Key parameters:
  - ON: The text column to search over
  - ATTRIBUTES: Columns available for filtering results
  - WAREHOUSE: Used for index creation and refreshes
  - TARGET_LAG: How fresh the index stays relative to source data
  - AS: Source query defining what gets indexed
-----------------------------------------------------------------------------*/
CREATE OR REPLACE CORTEX SEARCH SERVICE HR_POLICIES_DB.DEV.POLICY_SEARCH
ON chunk --search column
ATTRIBUTES language, relative_path --attributes are the columns that you’ll be able to filter search results on
WAREHOUSE = CORTEX_DEMO_WH
TARGET_LAG='1 hour'
AS
(
SELECT
chunk,
RELATIVE_PATH,
FILE_URL,
LANGUAGE
FROM 
HR_POLICIES_DB.DEV.DOC_CHUNKS
);

-- Verify the service was created
SHOW CORTEX SEARCH SERVICES IN SCHEMA HR_POLICIES_DB.DEV;


/*-----------------------------------------------------------------------------
  STEP 2: SEARCH_PREVIEW — Query the search service from SQL
  Demonstrates hybrid search with natural language queries.
-----------------------------------------------------------------------------*/

-- Query 1: Simple search — "How much notice period do employees have to serve??"
SELECT SNOWFLAKE.CORTEX.SEARCH_PREVIEW(
  'HR_POLICIES_DB.DEV.POLICY_SEARCH',
  '{
    "query": "How much notice period do employees have to serve?",
    "columns": ["chunk","relative_path"],
    "limit": 3
  }'
) AS SEARCH_RESULTS;


/*-----------------------------------------------------------------------------
  STEP 3: RAG PATTERN — Search + AI_COMPLETE for grounded answers
  Retrieve relevant documents, then use them as context for LLM generation.
  This is the enterprise chatbot pattern.
-----------------------------------------------------------------------------*/

-- RAG Example 1: Employee question about notice period
WITH SEARCH_RESULTS AS (
    SELECT PARSE_JSON(
        SNOWFLAKE.CORTEX.SEARCH_PREVIEW(
            'HR_POLICIES_DB.DEV.POLICY_SEARCH',
                '{
                    "query": "How much notice period do employees have to serve?",
                    "columns": ["chunk","relative_path"],
                    "limit": 3
                }'
        )
    ) AS RESULTS
),
CONTEXT_DOCS AS (
    SELECT LISTAGG(
        '[Source: ' || r.value:relative_path::STRING || '] ' || r.value:chunk::STRING,
        ' | '
    ) AS COMBINED_CONTEXT
    FROM SEARCH_RESULTS, LATERAL FLATTEN(input => RESULTS:results) r
)
SELECT SNOWFLAKE.CORTEX.AI_COMPLETE(
    'claude-sonnet-4-5',
    'You are a helpful HR policy assistant. Answer the question based ONLY on the provided sources.
     Cite your sources in brackets. If the answer is not in the sources, say so.\n\nSOURCES:\n'
    || COMBINED_CONTEXT
    || '\n\nQUESTION: How much notice period do employees have to serve?\nANSWER:'
) AS RAG_ANSWER
FROM CONTEXT_DOCS;