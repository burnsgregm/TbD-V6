import json
import os
import time
import vertexai
from vertexai.generative_models import GenerativeModel, Part
import asyncio 
from typing import List, Dict, Any

# --- Configuration ---
PROJECT_ID = os.environ.get("GCP_PROJECT_ID", "tbd-v2") 
LOCATION = "us-central1"
MODEL_NAME = "gemini-2.5-pro" 
OUTPUT_FILE = "v4_lstm_training_sequences.json"
TARGET_VOLUME = 1000
SEQUENCES_PER_PROMPT = 20
DOMAINS = ["Windows Troubleshooting", "Web App Configuration", "Medical Lab Procedure", "IT Support Workflow", "Desktop Publishing"]

# Initialize Vertex AI
try:
    vertexai.init(project=PROJECT_ID, location=LOCATION)
except Exception as e:
    print(f"CRITICAL ERROR: Failed to initialize Vertex AI locally. Ensure 'gcloud auth application-default login' is run.")
    print(e)
    # The program will continue but API calls will fail if auth is missing.

async def generate_sequences(model: GenerativeModel, sequence_count: int, domain: str) -> List[List[str]]:
    """
    Prompts Gemini to generate a list of structured procedural sequences.
    """
    prompt = f"""
    Generate {sequence_count} unique, realistic, step-by-step procedural action sequences for a user performing a task in the '{domain}' domain.
    
    Each sequence must be a list of short strings (3-7 words each), where each string is a user action. The final output MUST be a single JSON object containing one key: "sequences", which holds a JSON array of these sequences.
    
    Example: {{"sequences": [["Right click desktop", "Select Personalize", "Click Background"], ["Open Start Menu", "Search for CMD", "Run as administrator"], ...]}}
    """
    
    try:
        response = await model.generate_content_async(
            contents=[prompt],
            generation_config={
                "temperature": 0.5,
                "max_output_tokens": 8192,
                "response_mime_type": "application/json"
            }
        )
        
        raw_text = response.text.strip()
        data = json.loads(raw_text)
        return data.get("sequences", [])
        
    except Exception as e:
        # We now expect to see a real API error here if the connection fails
        print(f"--- API FAILED for {domain} with ERROR: {e} ---")
        return []

# FIX: Renamed and made asynchronous
async def main():
    if os.path.exists(OUTPUT_FILE):
        print(f"Appending to existing file: {OUTPUT_FILE}")
        with open(OUTPUT_FILE, 'r') as f:
            try:
                f.seek(0)
                all_sequences = json.load(f)
            except (json.JSONDecodeError, EOFError):
                all_sequences = []
    else:
        all_sequences = []

    model = GenerativeModel(MODEL_NAME)
    
    cycles_needed = TARGET_VOLUME // SEQUENCES_PER_PROMPT
    current_cycle = len(all_sequences) // SEQUENCES_PER_PROMPT
    
    print(f"Target: {TARGET_VOLUME} sequences. Starting at cycle {current_cycle} out of {cycles_needed}.")
    
    for i in range(current_cycle, cycles_needed):
        domain = DOMAINS[i % len(DOMAINS)]
        start_time = time.time()
        
        # FIX: Await the function call instead of running asyncio.run()
        new_sequences = await generate_sequences(model, SEQUENCES_PER_PROMPT, domain)
        
        if new_sequences:
            all_sequences.extend(new_sequences)
            
        elapsed = time.time() - start_time
        current_count = len(all_sequences)
        
        print(f"Cycle {i+1}/{cycles_needed} | Generated {len(new_sequences)} seqs in {elapsed:.2f}s | Total: {current_count}/{TARGET_VOLUME}")
        
        # Save progress after every cycle
        with open(OUTPUT_FILE, 'w') as f:
            json.dump(all_sequences, f, indent=2)

    print("\n--- Data Generation Complete ---")
    print(f"Final sequences saved to {OUTPUT_FILE}")
    
if __name__ == "__main__":
    # FIX: Call the async main function once
    asyncio.run(main())