"""Local keyword retrieval over the demonstration underwriting guidelines."""
import re
from functools import lru_cache
from pathlib import Path
from rank_bm25 import BM25Okapi

CORPUS_DIR = Path(__file__).parent / "corpus"


def tokenize(text: str) -> list[str]:
    return re.findall(r"\b[a-zA-Z0-9_-]{2,}\b", text.lower())


class GuidelineStore:
    @lru_cache(maxsize=1)
    def _index(self):
        documents = []
        for path in sorted(CORPUS_DIR.glob("*.md")):
            for section in path.read_text(encoding="utf-8").split("## "):
                if tokenize(section):
                    documents.append({"content": section.strip(), "metadata": {"source": path.name}})
        index = BM25Okapi([tokenize(doc["content"]) for doc in documents]) if documents else None
        return documents, index

    def retrieve_guidelines(self, query: str, n_results: int = 3) -> list[dict]:
        documents, index = self._index()
        if index is None:
            return []
        scores = index.get_scores(tokenize(query))
        ranked = sorted(range(len(documents)), key=lambda i: scores[i], reverse=True)
        return [dict(documents[i], score=round(float(scores[i]), 4))
                for i in ranked if scores[i] > 0][:n_results]


vector_store = GuidelineStore()
