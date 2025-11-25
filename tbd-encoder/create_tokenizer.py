import pickle
import os
# In the container (TF 2.15), this import is standard and guaranteed to work.
from tensorflow.keras.preprocessing.text import Tokenizer

print("--- Generating V6 Compatible Tokenizer inside Container ---")

corpus = [
    "User clicks File menu", "User selects Save As", "User types filename",
    "User clicks Save button", "User right-clicks Desktop", "User selects Personalize",
    "User clicks Background dropdown", "User selects Picture", "User selects Solid Color",
    "User selects Slideshow", "User clicks Close button"
]

# Initialize
tokenizer = Tokenizer(num_words=1000, oov_token="<OOV>")
tokenizer.fit_on_texts(corpus)

# Save
output_file = "tokenizer.pickle"
with open(output_file, 'wb') as handle:
    pickle.dump(tokenizer, handle, protocol=4)

print(f"SUCCESS: Created '{output_file}' ({os.path.getsize(output_file)} bytes)")