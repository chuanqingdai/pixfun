"""Conservative rejection of runaway ASR repetition; never silently rewrites speech."""
import re
import math
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


def checked_cues(cues, duration=None):
    good, rejected = [], 0
    for cue in cues:
        text = str(cue.get('text', ''))
        invalid_range = False
        if duration is not None:
            start, end = cue.get('start'), cue.get('end')
            valid_numbers = all(isinstance(v,(int,float)) and not isinstance(v,bool) and math.isfinite(v) for v in (start,end))
            invalid_range = not valid_numbers or not (0 <= start < end <= duration + .04)
        if repetitive(text) or '\ufffd' in text or invalid_range:
            rejected += 1
        else:
            good.append(cue)
    return good, rejected
