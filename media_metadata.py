"""Read capture facts from container metadata; never geocode or guess a place."""
import math
import re


def location_from_tags(tags):
    tags = {str(k).lower(): v for k, v in tags.items()}
    def value(*keys):
        return next((str(tags[k]).strip() for k in keys if isinstance(tags.get(k), str) and tags[k].strip()), None)
    name = value('com.apple.quicktime.location.name', 'location_name')
    if name: name = name[:200]
    raw = value('com.apple.quicktime.location.iso6709', 'location', 'location-eng')
    result = {'name': name, 'source': 'file-metadata'} if name else {}
    if raw:
        # ISO 6709 compact decimal degrees, degrees/minutes, or degrees/minutes/seconds.
        match = re.fullmatch(r'([+-]\d+(?:\.\d+)?)([+-]\d+(?:\.\d+)?)(?:([+-]\d+(?:\.\d+)?))?/?', raw)
        if match:
            def degrees(text, degree_digits):
                number = text[1:]; whole = number.split('.')[0]
                if len(whole) == degree_digits: converted = float(number)
                elif len(whole) in (degree_digits+2, degree_digits+4):
                    deg = float(number[:degree_digits]); rest = number[degree_digits:]
                    minutes = float(rest) if len(whole) == degree_digits+2 else float(rest[:2])
                    seconds = 0 if len(whole) == degree_digits+2 else float(rest[2:])
                    if minutes >= 60 or seconds >= 60: raise ValueError('Invalid coordinate')
                    converted = deg + minutes/60 + seconds/3600
                else: raise ValueError('Invalid coordinate')
                return -converted if text[0] == '-' else converted
            try:
                latitude, longitude = degrees(match[1], 2), degrees(match[2], 3)
                if not (-90 <= latitude <= 90 and -180 <= longitude <= 180): raise ValueError('Out of range')
                result.update(latitude=latitude, longitude=longitude, source='file-metadata')
                if match[3] and math.isfinite(float(match[3])): result['altitude'] = float(match[3])
            except ValueError: pass
    return result or None
