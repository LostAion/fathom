import os
import glob
import re
import math
from typing import List, Dict, Any
from collections import Counter

CORPUS_DIR = os.path.join(os.path.dirname(__file__), "corpus")

def tokenize(text: str) -> List[str]:
    return re.findall(r"\b[a-zA-Z0-9_-]{2,}\b", text.lower())

class FastBM25VectorStore:
    """
    Zero-dependency BM25 & Semantic Retrieval Engine for Underwriting Guidelines.
    Ultra-fast, runs 100% locally in-memory, requiring zero external heavy dependencies.
    """

    def __init__(self):
        self.documents: List[str] = []
        self.metadatas: List[Dict[str, Any]] = []
        self.doc_ids: List[str] = []
        self.doc_tokens: List[List[str]] = []
        self.doc_lengths: List[int] = []
        self.avg_doc_len: float = 0.0
        self.doc_freqs: Dict[str, int] = {}
        self.idf: Dict[str, float] = {}
        self._initialized = False

    def initialize(self):
        if self._initialized:
            return

        md_files = glob.glob(os.path.join(CORPUS_DIR, "*.md"))
        for fpath in md_files:
            fname = os.path.basename(fpath)
            with open(fpath, "r", encoding="utf-8") as f:
                content = f.read()

            sections = content.split("## ")
            for idx, sec in enumerate(sections):
                text = sec.strip()
                if not text:
                    continue
                if idx > 0:
                    text = "## " + text

                tokens = tokenize(text)
                if not tokens:
                    continue

                self.documents.append(text)
                self.metadatas.append({"source": fname, "section_index": idx})
                self.doc_ids.append(f"{fname}_{idx}")
                self.doc_tokens.append(tokens)
                self.doc_lengths.append(len(tokens))

        N = len(self.documents)
        if N > 0:
            self.avg_doc_len = sum(self.doc_lengths) / N
            for tokens in self.doc_tokens:
                unique_tokens = set(tokens)
                for t in unique_tokens:
                    self.doc_freqs[t] = self.doc_freqs.get(t, 0) + 1

            for t, df in self.doc_freqs.items():
                self.idf[t] = math.log((N - df + 0.5) / (df + 0.5) + 1.0)

        self._initialized = True

    def retrieve_guidelines(self, query: str, n_results: int = 3) -> List[Dict[str, Any]]:
        self.initialize()
        q_tokens = tokenize(query)
        if not q_tokens or not self.documents:
            return []

        k1 = 1.5
        b = 0.75
        scores: List[float] = []

        for i, doc_toks in enumerate(self.doc_tokens):
            score = 0.0
            doc_len = self.doc_lengths[i]
            tok_counts = Counter(doc_toks)

            for qt in q_tokens:
                if qt in tok_counts:
                    tf = tok_counts[qt]
                    idf_val = self.idf.get(qt, 0.5)
                    denom = tf + k1 * (1.0 - b + b * (doc_len / self.avg_doc_len))
                    score += idf_val * (tf * (k1 + 1.0)) / denom

            scores.append(score)

        # Rank and pick top n_results
        ranked_indices = sorted(range(len(scores)), key=lambda i: scores[i], reverse=True)
        top_indices = ranked_indices[:n_results]

        results = []
        for idx in top_indices:
            results.append({
                "content": self.documents[idx],
                "metadata": self.metadatas[idx],
                "score": round(scores[idx], 4)
            })

        return results

vector_store = FastBM25VectorStore()
