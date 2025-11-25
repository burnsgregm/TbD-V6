import pickle
import os
import sys

print(f"Python Executable: {sys.executable}")

# Try imports in order of preference for TF 2.15 compatibility
try:
    # 1. Standard TF 2.x import
    from tensorflow.keras.preprocessing.text import Tokenizer
    print("SUCCESS: Imported Tokenizer from tensorflow.keras")
except ImportError:
    try:
        # 2. Fallback for newer TF environments or specific Keras installs
        from keras.preprocessing.text import Tokenizer
        print("SUCCESS: Imported Tokenizer from keras (standalone)")
    except ImportError:
        try:
            # 3. Fallback for TF 2.16+ legacy support path
            from tf_keras.preprocessing.text import Tokenizer
            print("SUCCESS: Imported Tokenizer from tf_keras")
        except ImportError:
            print("FATAL: Could not import Tokenizer. Ensure tensorflow is installed.")
            sys.exit(1)

# Define a basic vocabulary consistent with your V4 training data
corpus = [
    "User clicks File menu",
    "User selects Save As",
    "User types filename",
    "User clicks Save button",
    "User right-clicks Desktop",
    "User selects Personalize",
    "User clicks Background dropdown",
    "User selects Picture",
    "User selects Solid Color",
    "User selects Slideshow",
    "User clicks Close button"
]

# Initialize and fit
try:
    tokenizer = Tokenizer(num_words=1000, oov_token="<OOV>")
    tokenizer.fit_on_texts(corpus)

    # Test the tokenizer
    seq = tokenizer.texts_to_sequences(["User clicks Save"])
    print(f"Test Sequence: {seq}")

    # Save using standard pickle protocol (compatible across versions)
    output_file = "tokenizer.pickle"
    with open(output_file, 'wb') as handle:
        pickle.dump(tokenizer, handle, protocol=4)

    print(f"SUCCESS: Created compatible '{output_file}'")
    print(f"File size: {os.path.getsize(output_file)} bytes")

except Exception as e:
    print(f"FATAL ERROR during tokenization/saving: {e}")