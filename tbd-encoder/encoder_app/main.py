import os
import pickle
import numpy as np
import tensorflow as tf
from tensorflow.keras.models import Model, Sequential
from tensorflow.keras.layers import Input, Embedding, LSTM, Dense
from tensorflow.keras.preprocessing.sequence import pad_sequences
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
from typing import List

# --- Configuration ---
LSTM_UNITS = 512
MAX_SEQUENCE_LENGTH = 100
MODEL_PATH = "lstm_model.h5"
TOKENIZER_PATH = "tokenizer.pickle"
ENCODING_METHOD = "LSTM_512_V6_REBUILD"

# --- V6 FIX: Hardcoded Dimensions to match Pre-trained Weights ---
# Based on error: "assigned value shape (2525, 128)"
VOCAB_SIZE_WEIGHTS = 2525
EMBEDDING_DIM_WEIGHTS = 128

# --- Data Models ---
class SequenceInput(BaseModel):
    sequence: List[str]

class VectorOutput(BaseModel):
    temporal_context_vector: List[float]
    temporal_encoding_method: str

# --- Global State ---
tokenizer = None
encoder_model = None

# --- V6: The Architecture Rebuild Logic ---
def build_and_load_model():
    global tokenizer, encoder_model
    print("--- Starting V6 Model Rebuild (Hardcoded Dimensions) ---")

    # 1. Load Tokenizer
    try:
        with open(TOKENIZER_PATH, 'rb') as handle:
            tokenizer = pickle.load(handle)
        print(f"Tokenizer loaded. Real Vocab Size: {len(tokenizer.word_index) + 1}")
    except Exception as e:
        print(f"FATAL: Could not load tokenizer. {e}")
        return

    # 2. Reconstruct the Architecture
    # CRITICAL FIX: We act as if the vocab size is 2525, even if the tokenizer is smaller.
    # This aligns the layer shape with the weight file.
    try:
        rebuilt_model = Sequential([
            Input(shape=(MAX_SEQUENCE_LENGTH - 1,), name='input_sequence'),
            Embedding(input_dim=VOCAB_SIZE_WEIGHTS, 
                      output_dim=EMBEDDING_DIM_WEIGHTS, 
                      name='embedding_layer'),
            LSTM(LSTM_UNITS, return_sequences=False, name='temporal_context_encoder'),
            # The dense layer must also match the vocab size of the weights
            Dense(VOCAB_SIZE_WEIGHTS, activation='softmax', name='output_layer')
        ])
        
        # 3. Load Weights
        rebuilt_model.load_weights(MODEL_PATH)
        print("Raw weights loaded successfully into rebuilt architecture.")

        # 4. Extract the Encoder
        encoder_model = Model(
            inputs=rebuilt_model.inputs,
            outputs=rebuilt_model.get_layer('temporal_context_encoder').output
        )
        print("Temporal Encoder Service (V6) is ready.")

    except Exception as e:
        print(f"FATAL: Model reconstruction failed: {e}")
        encoder_model = None

# --- Application Startup ---
app = FastAPI(title="TbD V6 Temporal Encoder")

@app.on_event("startup")
async def startup_event():
    build_and_load_model()

# --- Endpoints ---
@app.post("/encode_sequence", response_model=VectorOutput)
def encode_sequence(input_data: SequenceInput):
    if encoder_model is None or tokenizer is None:
        return VectorOutput(
            temporal_context_vector=[0.0] * LSTM_UNITS,
            temporal_encoding_method="FAILED_V6_INIT"
        )

    try:
        # Tokenize
        token_ids = tokenizer.texts_to_sequences(input_data.sequence)
        flat_tokens = [item for sublist in token_ids for item in sublist]

        # Pad
        padded = pad_sequences(
            [flat_tokens], 
            maxlen=MAX_SEQUENCE_LENGTH - 1, 
            padding='pre', 
            truncating='pre'
        )

        # Predict
        vector = encoder_model.predict(padded, verbose=0)[0]

        return VectorOutput(
            temporal_context_vector=vector.tolist(),
            temporal_encoding_method=ENCODING_METHOD
        )

    except Exception as e:
        print(f"Runtime Encoding Error: {e}")
        return VectorOutput(
            temporal_context_vector=[0.0] * LSTM_UNITS,
            temporal_encoding_method="FAILED_RUNTIME_ERROR"
        )