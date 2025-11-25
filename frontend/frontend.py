import streamlit as st
import requests
import time
import uuid
import json
import os
from google.cloud import storage
from google.oauth2 import service_account
from google.api_core.exceptions import Forbidden

# --- Configuration ---
try:
    PROJECT_ID = st.secrets["gcp"]["project_id"]
    DISPATCHER_URL = st.secrets["gcp"]["dispatcher_url"]
    INPUT_BUCKET_NAME = st.secrets["gcp"]["input_bucket"]
    OUTPUT_BUCKET_NAME = st.secrets["gcp"]["output_bucket"]
except FileNotFoundError:
    st.error("Secrets file not found. Please configure secrets.toml.")
    st.stop()

# --- App Setup ---
st.set_page_config(page_title="TbD V6 Test Console", layout="wide")
st.title("Teach by Doing (TbD) V6 - Test Console")
st.markdown(f"**Project:** {PROJECT_ID} | **Dispatcher:** {DISPATCHER_URL}")

# --- Authentication ---
@st.cache_resource
def get_storage_client():
    try:
        if "gcp_service_account" in st.secrets:
            service_account_info = st.secrets["gcp_service_account"]
            credentials = service_account.Credentials.from_service_account_info(service_account_info)
            return storage.Client(credentials=credentials, project=PROJECT_ID)
        else:
            return storage.Client(project=PROJECT_ID)
    except Exception as e:
        st.error(f"Failed to authenticate with GCP: {e}")
        return None

storage_client = get_storage_client()
if not storage_client:
    st.stop()

# --- Sidebar: Status Check (Object-Level) ---
st.sidebar.header("System Status")

def check_bucket_access(bucket_name):
    """
    Verifies access by attempting to list objects (requires storage.objects.list).
    This works with 'Storage Object Admin' role, whereas get_bucket() requires 'storage.buckets.get'.
    """
    try:
        bucket = storage_client.bucket(bucket_name)
        # Attempt to list 1 blob to verify read permissions
        blobs = list(bucket.list_blobs(max_results=1))
        return True, "OK"
    except Forbidden:
        return False, "Permission Denied (403)"
    except Exception as e:
        # If bucket doesn't exist, list_blobs often returns 404 NotFound which catches here
        return False, f"Error: {e}"

# Check Input Bucket
access_in, msg_in = check_bucket_access(INPUT_BUCKET_NAME)
if access_in:
    st.sidebar.success(f"Input Bucket: {INPUT_BUCKET_NAME}")
else:
    st.sidebar.error(f"Input Bucket Error: {msg_in}")

# Check Output Bucket
access_out, msg_out = check_bucket_access(OUTPUT_BUCKET_NAME)
if access_out:
    st.sidebar.success(f"Output Bucket: {OUTPUT_BUCKET_NAME}")
else:
    st.sidebar.error(f"Output Bucket Error: {msg_out}")


# --- Main Workflow ---
col1, col2 = st.columns(2)

with col1:
    st.subheader("1. Upload Video")
    uploaded_file = st.file_uploader("Choose an MP4 video", type=["mp4"])

    if uploaded_file:
        if 'task_id' not in st.session_state:
            st.session_state.task_id = str(uuid.uuid4())
        
        task_id = st.session_state.task_id
        st.info(f"Session Task ID: {task_id}")

        if st.button("Upload to GCS"):
            try:
                bucket = storage_client.bucket(INPUT_BUCKET_NAME)
                blob_name = f"{task_id}/{uploaded_file.name}"
                blob = bucket.blob(blob_name)
                
                with st.spinner("Uploading video to GCS..."):
                    blob.upload_from_file(uploaded_file, content_type="video/mp4")
                
                gcs_uri = f"gs://{INPUT_BUCKET_NAME}/{blob_name}"
                st.session_state.gcs_uri = gcs_uri
                st.success(f"Uploaded to: {gcs_uri}")
            except Exception as e:
                st.error(f"Upload Failed: {e}")

with col2:
    st.subheader("2. Dispatch Task")
    if 'gcs_uri' in st.session_state:
        st.write(f"**Target Video:** {st.session_state.gcs_uri}")
        
        if st.button("Submit to Dispatcher API"):
            payload = {
                "task_id": st.session_state.task_id,
                "client_id": "streamlit-cloud-console",
                "gcs_uri": st.session_state.gcs_uri,
                "output_bucket": OUTPUT_BUCKET_NAME
            }
            
            try:
                with st.spinner("Contacting Dispatcher..."):
                    # Strip any trailing slash from the URL just in case
                    base_url = DISPATCHER_URL.rstrip('/')
                    api_url = f"{base_url}/submit"
                    response = requests.post(api_url, json=payload, timeout=10)
                    
                    if response.status_code == 202:
                        st.success("Task Accepted (202)")
                        st.json(response.json())
                        st.session_state.job_running = True
                    else:
                        st.error(f"Error {response.status_code}: {response.text}")
            except Exception as e:
                st.error(f"API Request Failed: {e}")

# --- Results Section ---
st.divider()
st.subheader("3. Await Results")

if 'job_running' in st.session_state and st.session_state.job_running:
    result_blob_name = f"{st.session_state.task_id}/pathway.json"
    
    if st.button("Check for Result Now"):
        try:
            bucket = storage_client.bucket(OUTPUT_BUCKET_NAME)
            blob = bucket.blob(result_blob_name)
            # exists() does a metadata check which might fail with Object Admin role
            # Try reloading the blob instead
            try:
                blob.reload()
                exists = True
            except:
                exists = False
                
            if exists:
                st.success("Result Found!")
                json_data = blob.download_as_text()
                st.download_button("Download JSON", json_data, "pathway.json", "application/json")
                with st.expander("View Raw JSON"):
                    st.code(json_data, language='json')
            else:
                st.warning("Result not yet available. The Worker is likely still processing.")
        except Exception as e:
            st.error(f"Check Failed: {e}")