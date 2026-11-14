"""Human-readable names for map regions (English + Hindi).

Boxes are [lon_min, lat_min, lon_max, lat_max]; lon_min > lon_max wraps the
dateline. The smallest box containing a point wins. Deliberately coarse:
these name *areas*, they do not draw borders.
"""
from __future__ import annotations

NAMED = [
    ("North-West India", "उत्तर-पश्चिम भारत", [68, 22, 78.5, 32.5]),
    ("Indo-Gangetic Plain", "सिंधु-गंगा का मैदान", [76, 23, 89, 31]),
    ("Central India", "मध्य भारत", [73, 17, 85, 25]),
    ("South India", "दक्षिण भारत", [72, 7, 81, 18]),
    ("North-East India", "पूर्वोत्तर भारत", [89, 21, 97.5, 29.5]),
    ("Himalaya & Tibetan Plateau", "हिमालय और तिब्बती पठार", [72, 27, 104, 40]),
    ("Bay of Bengal", "बंगाल की खाड़ी", [80, 5, 95, 22]),
    ("Arabian Sea", "अरब सागर", [52, 5, 73, 25]),
    ("Pakistan & Afghanistan", "पाकिस्तान और अफ़ग़ानिस्तान", [60, 24, 75, 38]),
    ("South Asia", "दक्षिण एशिया", [60, 5, 100, 38]),
    ("Middle East", "मध्य-पूर्व", [34, 12, 62, 40]),
    ("Central Asia", "मध्य एशिया", [50, 35, 90, 55]),
    ("China", "चीन", [97, 20, 125, 45]),
    ("Japan & Korea", "जापान और कोरिया", [124, 30, 146, 46]),
    ("South-East Asia", "दक्षिण-पूर्व एशिया", [92, -11, 141, 22]),
    ("Siberia", "साइबेरिया", [60, 50, 180, 78]),
    ("Sahel", "साहेल", [-17, 10, 40, 18]),
    ("Sahara", "सहारा", [-17, 18, 35, 33]),
    ("Central Africa", "मध्य अफ़्रीका", [8, -10, 32, 10]),
    ("East Africa", "पूर्वी अफ़्रीका", [32, -12, 52, 15]),
    ("Southern Africa", "दक्षिणी अफ़्रीका", [10, -35, 41, -10]),
    ("Mediterranean", "भूमध्य सागर क्षेत्र", [-10, 30, 40, 45]),
    ("Scandinavia", "स्कैंडिनेविया", [4, 55, 32, 72]),
    ("Europe", "यूरोप", [-11, 35, 45, 72]),
    ("Greenland", "ग्रीनलैंड", [-75, 59, -10, 84]),
    ("North Atlantic (south of Greenland)", "उत्तरी अटलांटिक (ग्रीनलैंड के दक्षिण में)", [-60, 45, -10, 64]),
    ("North Atlantic", "उत्तरी अटलांटिक", [-80, 20, 0, 66]),
    ("Tropical Atlantic", "उष्णकटिबंधीय अटलांटिक", [-60, -20, 15, 20]),
    ("South Atlantic", "दक्षिणी अटलांटिक", [-60, -60, 20, -20]),
    ("Alaska & Western Canada", "अलास्का और पश्चिमी कनाडा", [-170, 50, -110, 72]),
    ("Canada", "कनाडा", [-140, 45, -52, 76]),
    ("United States", "संयुक्त राज्य अमेरिका", [-125, 25, -66, 50]),
    ("Mexico & Central America", "मेक्सिको और मध्य अमेरिका", [-118, 7, -77, 32]),
    ("Amazon", "अमेज़न", [-75, -15, -45, 5]),
    ("South America", "दक्षिण अमेरिका", [-82, -56, -34, 13]),
    ("Australia", "ऑस्ट्रेलिया", [112, -45, 155, -10]),
    ("Eastern Pacific", "पूर्वी प्रशांत महासागर", [-150, -20, -80, 20]),
    ("Western Pacific", "पश्चिमी प्रशांत महासागर", [120, -20, 180, 25]),
    ("North Pacific", "उत्तरी प्रशांत महासागर", [140, 25, -120, 62]),
    ("South Pacific", "दक्षिणी प्रशांत महासागर", [150, -60, -70, -20]),
    ("Indian Ocean", "हिंद महासागर", [40, -45, 110, 5]),
    ("Arctic Ocean", "आर्कटिक महासागर", [-180, 75, 180, 90]),
    ("Southern Ocean", "दक्षिणी महासागर", [-180, -66, 180, -45]),
    ("Antarctica", "अंटार्कटिका", [-180, -90, 180, -63]),
]


def _contains(box, lat: float, lon: float) -> bool:
    lon0, lat0, lon1, lat1 = box
    if not (lat0 <= lat <= lat1):
        return False
    return lon0 <= lon <= lon1 if lon0 <= lon1 else (lon >= lon0 or lon <= lon1)


def _area(box) -> float:
    lon0, lat0, lon1, lat1 = box
    width = lon1 - lon0 if lon0 <= lon1 else (180 - lon0) + (lon1 + 180)
    return width * (lat1 - lat0)


def name_for(lat: float, lon: float) -> tuple[str, str]:
    hits = [(_area(b), en, hi) for en, hi, b in NAMED if _contains(b, lat, lon)]
    if hits:
        _, en, hi = min(hits)
        return en, hi
    ns = "N" if lat >= 0 else "S"
    ew = "E" if lon >= 0 else "W"
    label = f"Around {abs(lat):.0f}°{ns}, {abs(lon):.0f}°{ew}"
    return label, f"{abs(lat):.0f}°{ns}, {abs(lon):.0f}°{ew} के आसपास"
