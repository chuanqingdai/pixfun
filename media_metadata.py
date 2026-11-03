"""Read capture facts from container metadata; never geocode or guess a place."""
import math
import re
import hashlib


def device_id_from_tags(tags):
    """Opaque identity only from an explicit camera serial, never a model/folder."""
    tags = {str(k).lower(): str(v).strip() for k, v in tags.items() if v is not None}
    serial = tags.get('com.apple.quicktime.camera.serial') or tags.get('bodyserialnumber')
    if not serial or serial.lower() in ('unknown', '0', 'none'): return None
    make = tags.get('make', tags.get('com.apple.quicktime.make', ''))
    model = tags.get('model', tags.get('com.apple.quicktime.model', ''))
    return 'camera-sha256:' + hashlib.sha256((make + '\0' + model + '\0' + serial).encode()).hexdigest()


def nonnegative_number(raw):
    if isinstance(raw, bool): return None
    try:
        value = float(raw)
        return value if math.isfinite(value) and value >= 0 else None
    except (ValueError, TypeError, ZeroDivisionError): return None


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
    if 'latitude' in result:
        accuracy = nonnegative_number(tags.get('com.apple.quicktime.location.accuracy.horizontal'))
        if accuracy is not None: result['horizontalAccuracy'] = accuracy
        datum = value('gpsmapdatum')
        if datum: result['datum'] = datum[:80]
    return result or None


def photo_capture_metadata(source):
    """Read the original photo, not a decoded preview. No inferred timezone or place."""
    from PIL import Image
    with Image.open(source) as photo:
        exif = photo.getexif()
        detail = exif.get_ifd(34665) if 34665 in exif else {}
        gps = exif.get_ifd(34853) if 34853 in exif else {}
        tags = {'make': exif.get(271), 'model': exif.get(272), 'bodyserialnumber': detail.get(42033)}
        result = {'camera': tags['model'], 'captureDeviceID': device_id_from_tags(tags),
                  'capturedAt': None, 'dateSource': None, 'location': None, 'captureMetadataVersion': 2}
        raw = detail.get(36867)
        offset = detail.get(36881)
        if isinstance(raw, str) and re.fullmatch(r'\d{4}:\d{2}:\d{2} \d{2}:\d{2}:\d{2}', raw):
            result['capturedAt'] = raw[:10].replace(':', '-') + 'T' + raw[11:]
            if isinstance(offset, str) and re.fullmatch(r'[+-]\d{2}:\d{2}', offset): result['capturedAt'] += offset
            result['dateSource'] = 'EXIF DateTimeOriginal'
        if gps:
            try:
                def coordinate(values, ref, positive, negative):
                    if ref not in (positive, negative) or len(values) != 3: raise ValueError('Invalid GPS')
                    d, m, s = map(float, values)
                    if not all(math.isfinite(x) for x in (d, m, s)) or d < 0 or not 0 <= m < 60 or not 0 <= s < 60: raise ValueError('Invalid GPS')
                    return (d + m / 60 + s / 3600) * (-1 if ref == negative else 1)
                lat = coordinate(gps[2], gps[1], 'N', 'S')
                lon = coordinate(gps[4], gps[3], 'E', 'W')
                if not (-90 <= lat <= 90 and -180 <= lon <= 180): raise ValueError('Invalid GPS')
                loc = dict(latitude=lat, longitude=lon, source='file-metadata')
                if isinstance(gps.get(18), str): loc['datum'] = gps[18][:80]
                accuracy = nonnegative_number(gps.get(31))
                if accuracy is not None: loc['horizontalAccuracy'] = accuracy
                result['location'] = loc
            except (KeyError, TypeError, ValueError, ZeroDivisionError, OverflowError): pass
        return result
