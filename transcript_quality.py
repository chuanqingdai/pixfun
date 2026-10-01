"""Conservative rejection of runaway ASR repetition; never silently rewrites speech."""
import re
from collections import Counter


def repetitive(text):
    words = re.findall(r"\w+", str(text).casefold())
    if len(words) < 16:
        return False
    # A repeated one-to-four-word phrase occupying >80% of a long cue is suspect.
    for width in range(1, 5):
        for offset in range(min(width, len(words))):
            chunks = [tuple(words[i:i + width]) for i in range(offset, len(words) - width + 1, width)]
            if len(chunks) >= 8 and max(Counter(chunks).values()) / len(chunks) >= 0.8:
                return True
    return False


def checked_cues(cues):
    good, rejected = [], 0
    for cue in cues:
        if repetitive(cue.get("text", "")):
            rejected += 1
        else:
            good.append(cue)
    return good, rejected
