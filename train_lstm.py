import json
import numpy as np
import tensorflow as tf
from tensorflow.keras.preprocessing.text import Tokenizer
from tensorflow.keras.preprocessing.sequence import pad_sequences
from tensorflow.keras.models import Model
from tensorflow.keras.layers import Input, Embedding, LSTM, Dense
import os # Included for os.path operations if needed

# --- Configuration ---
DATA_FILE = "v4_lstm_training_sequences.json"
MAX_SEQUENCE_LENGTH = 100
EMBEDDING_DIM = 128
LSTM_OUTPUT_DIM = 512 # As per TDD 3.1
OUTPUT_MODEL_FILE = "lstm_model.h5"

def load_and_preprocess_data():
    """Loads sequences and tokenizes them."""
    with open(DATA_FILE, 'r') as f:
        data = json.load(f)
    
    # Flatten the list of lists into a single list of actions
    all_actions = [step for sequence in data for step in sequence]
    
    # 1. Tokenization
    tokenizer = Tokenizer(num_words=None, oov_token="<unk>")
    tokenizer.fit_on_texts(all_actions)
    
    # Convert sequences of words into sequences of integers (Token IDs)
    tokenized_sequences = tokenizer.texts_to_sequences(data)
    
    # 2. Padding (Ensures all sequences are the same length for the LSTM)
    padded_sequences = pad_sequences(
        tokenized_sequences, 
        maxlen=MAX_SEQUENCE_LENGTH, 
        padding='post',
        truncating='post'
    )
    
    # Prepare X and Y: X is the input sequence, Y is the next token (target for prediction)
    X = padded_sequences[:, :-1]
    Y = padded_sequences[:, 1:]
    
    print(f"Total vocabulary size: {len(tokenizer.word_index)}")
    print(f"Total sequences for training: {len(padded_sequences)}")
    
    # Save the tokenizer object (required for service C to tokenize input sequences)
    import pickle
    with open('tokenizer.pickle', 'wb') as handle:
        pickle.dump(tokenizer, handle, protocol=pickle.HIGHEST_PROTOCOL)
    print("Tokenizer saved to tokenizer.pickle.")
    
    return X, Y, tokenizer

def build_and_train_lstm(X, Y, tokenizer):
    """Defines the LSTM architecture and performs the training run."""
    vocab_size = len(tokenizer.word_index) + 1
    
    # 1. Define Model Architecture (LSTM)
    input_layer = Input(shape=(MAX_SEQUENCE_LENGTH - 1,), name='input_sequence')
    
    embedding = Embedding(
        vocab_size, 
        EMBEDDING_DIM, 
        input_length=MAX_SEQUENCE_LENGTH - 1
    )(input_layer)
    
    # LSTM layer: Fixed-size 512D output (Temporal Context Vector)
    lstm_output = LSTM(
        LSTM_OUTPUT_DIM, 
        return_sequences=False, 
        name='temporal_context_encoder'
    )(embedding)
    
    # Final prediction layer (needed for the loss function, predicting the next token)
    output_layer = Dense(vocab_size, activation='softmax', name='prediction_output')(lstm_output)
    
    model = Model(inputs=input_layer, outputs=output_layer)
    
    # 2. Compile and Train
    model.compile(
        optimizer='adam', 
        loss='sparse_categorical_crossentropy', 
        metrics=['accuracy']
    )
    
    print(model.summary())
    
    # Slice the data to fit memory constraints, using all 1000 sequences
    train_size = len(X) 
    
    # The target array (Y) needs to be simplified to match the output layer shape
    # We use the token ID of the last element in the sequence slice as the symbolic target
    y_train = Y[:, -1]

    # --- UPDATED EPOCH COUNT ---
    model.fit(
        X, 
        y_train, 
        epochs=15, # <-- THE CHANGE
        batch_size=32, 
        verbose=1
    )
    
    # 3. Save the Model
    model.save(OUTPUT_MODEL_FILE)
    print(f"\n? Model training complete. Weights saved to {OUTPUT_MODEL_FILE}")
    print(f"Ready to deploy Service C.")

if __name__ == "__main__":
    X, Y, tokenizer = load_and_preprocess_data()
    build_and_train_lstm(X, Y, tokenizer)