// Plain-language knowledge the guided investigation uses: topics, region presets,
// definitions of the live "My Place" variables, and the full reference list.

import 'package:flutter/material.dart';

class Topic {
  const Topic(this.key, this.icon, this.en, this.hi, this.words, this.power);
  final String key, en, hi;
  final IconData icon;
  final List<String> words; // matched against dataset id / sphere / short name
  final List<String> power; // NASA POWER variable keys for a single place
}

const kTopics = <Topic>[
  Topic('heat', Icons.thermostat, 'Heat', 'गर्मी', ['temp', 'lst', 't2m'], ['temp', 'hotdays']),
  Topic('rain', Icons.water_drop, 'Rain', 'बारिश', ['precip', 'imerg', 'rain'], ['rain', 'monsoon']),
  Topic('water', Icons.waves, 'Water in the ground', 'ज़मीन का पानी', ['grace', 'soil', 'runoff', 'evap'], ['soil']),
  Topic('green', Icons.grass, 'Greenery and crops', 'हरियाली और फ़सल', ['ndvi', 'green', 'soil'], ['soil', 'rain']),
  Topic('air', Icons.air, 'Air quality', 'हवा की गुणवत्ता', ['no2', 'co2', 'air', 'aerosol'], ['humid']),
  Topic('ice', Icons.ac_unit, 'Ice and snow', 'बर्फ़', ['ice', 'snow'], ['temp']),
];

class Preset {
  const Preset(this.en, this.hi, this.bbox, this.kind, this.kindHi);
  final String en, hi, kind, kindHi;
  final List<double> bbox; // west, south, east, north
}

const kPresets = <Preset>[
  Preset('India', 'भारत', [68, 8, 97, 35], 'country', 'देश'),
  Preset('North-West India', 'उत्तर-पश्चिम भारत', [69, 24, 78.5, 32.5], 'farm belt', 'कृषि क्षेत्र'),
  Preset('Goa and Konkan coast', 'गोवा और कोंकण तट', [72.5, 14, 75, 18.5], 'coast', 'तट'),
  Preset('Delhi region', 'दिल्ली क्षेत्र', [76, 27.5, 78.5, 29.5], 'big city', 'महानगर'),
  Preset('Sundarbans delta', 'सुंदरबन डेल्टा', [88, 21, 90.5, 23], 'tidal estuary', 'ज्वारीय मुहाना'),
  Preset('Thar Desert', 'थार रेगिस्तान', [69.5, 24.5, 74.5, 29], 'desert', 'रेगिस्तान'),
  Preset('Sahara', 'सहारा', [-10, 17, 30, 30], 'desert', 'रेगिस्तान'),
  Preset('Sahel', 'साहेल', [-15, 11, 35, 17], 'dry grassland', 'सूखी घासभूमि'),
  Preset('Amazon', 'अमेज़न', [-72, -12, -52, 2], 'rain forest', 'वर्षावन'),
  Preset('Congo Basin', 'कांगो बेसिन', [14, -6, 28, 4], 'rain forest', 'वर्षावन'),
  Preset('Tibetan Plateau', 'तिब्बत का पठार', [80, 29, 100, 36], 'high mountains', 'ऊँचे पहाड़'),
  Preset('Siberia', 'साइबेरिया', [70, 55, 130, 70], 'cold forest', 'ठंडा जंगल'),
  Preset('Western USA', 'पश्चिमी अमेरिका', [-123, 32, -105, 45], 'dry west', 'सूखा पश्चिम'),
  Preset('Mediterranean', 'भूमध्य क्षेत्र', [-9, 34, 30, 45], 'dry summers', 'सूखी गर्मियाँ'),
  Preset('East Africa', 'पूर्वी अफ़्रीका', [32, -5, 48, 12], 'drought-prone', 'सूखा-प्रवण'),
  Preset('Australia', 'ऑस्ट्रेलिया', [114, -38, 153, -12], 'continent', 'महाद्वीप'),
  Preset('Europe', 'यूरोप', [-10, 36, 30, 60], 'continent', 'महाद्वीप'),
  Preset('Arctic', 'आर्कटिक', [-180, 66, 180, 88], 'polar', 'ध्रुवीय'),
];

/// One-line meanings of the "My Place" variables (NASA POWER, built on MERRA-2).
const kPowerDefs = <String, (String, String)>{
  'temp': ('Average air temperature 2 m above the ground over the whole year.', 'पूरे साल का ज़मीन से 2 मीटर ऊपर हवा का औसत तापमान।'),
  'hotdays': ('Days hotter than what used to be the hottest 10% of days at this place.', 'ऐसे दिन जो इस जगह के पहले के सबसे गर्म 10% दिनों से भी गर्म रहे।'),
  'rain': ('All rain and snow that fell in the year.', 'साल भर में गिरी सारी बारिश और बर्फ़।'),
  'monsoon': ('Rain in the four monsoon months, June to September.', 'मानसून के चार महीनों (जून से सितंबर) की बारिश।'),
  'soil': ('How wet the soil is down to where roots reach (0% bone dry, 100% soaked).', 'जड़ों की गहराई तक मिट्टी कितनी गीली है (0% बिल्कुल सूखी, 100% तर)।'),
  'humid': ('How much water vapour the air holds compared with the most it could hold.', 'हवा में कितनी भाप है, उसकी अधिकतम क्षमता की तुलना में।'),
};

class Reference {
  const Reference(this.group, this.name, this.org, this.url, this.why, this.whyHi, {this.used = true});
  final String group, name, org, url, why, whyHi;
  final bool used; // true = its numbers or code are inside our results; false = guidance / link only
}

/// Everything used or consulted, with where it comes from and why. Datasets actually
/// computed with are listed above this in the app straight from the pipeline (with citations).
const kReferences = <Reference>[
  // NASA tools named on the challenge Resources tab
  Reference('NASA tools', 'NASA POWER API', 'NASA Langley Research Center', 'https://power.larc.nasa.gov/',
      'Live 40-year records for any tapped place (built on MERRA-2 and CERES).', 'किसी भी जगह का 40 साल का सीधा रिकॉर्ड (MERRA-2 और CERES पर आधारित)।'),
  Reference('NASA tools', 'Giovanni', 'NASA GES DISC', 'https://giovanni.gsfc.nasa.gov/giovanni/',
      'Its time-series files can be dropped into "Bring your own evidence"; our sample file follows its layout.', 'इसकी टाइम-सीरीज़ फ़ाइलें "अपना सबूत लाएँ" में डाली जा सकती हैं; नमूना फ़ाइल इसी ढाँचे में है।'),
  Reference('NASA tools', 'AppEEARS', 'NASA LP DAAC', 'https://appeears.earthdatacloud.nasa.gov/',
      'Point-sample files (e.g. MODIS vegetation) are accepted by the evidence reader.', 'इसकी पॉइंट-सैंपल फ़ाइलें (जैसे MODIS हरियाली) सबूत-रीडर में चलती हैं।'),
  Reference('NASA tools', 'Hydrology Time Series (Data Rods)', 'NASA GES DISC', 'https://disc.gsfc.nasa.gov/information/tools?title=Hydrology%20Time%20Series',
      'Source of the GLDAS variables idea; its text files are accepted by the evidence reader.', 'GLDAS चरों का स्रोत-विचार; इसकी टेक्स्ट फ़ाइलें सबूत-रीडर में चलती हैं।', used: false),
  Reference('NASA tools', 'NASA Earth Observations (NEO)', 'NASA Goddard', 'https://neo.gsfc.nasa.gov/',
      'Light monthly maps of MODIS greenness, MODIS land heat and OMI NO₂.', 'MODIS हरियाली, MODIS ज़मीनी गर्मी और OMI NO₂ के हल्के मासिक नक़्शे।'),
  Reference('NASA tools', 'Earthdata Login + earthaccess', 'NASA ESDIS / NSIDC', 'https://github.com/nsidc/earthaccess',
      'Downloads GRACE, GLDAS, GPM IMERG and MERRA-2 files.', 'GRACE, GLDAS, GPM IMERG और MERRA-2 फ़ाइलें उतारता है।'),
  Reference('NASA tools', 'Climate Data Online (CDO)', 'NOAA NCEI', 'https://www.ncei.noaa.gov/cdo-web/',
      'Station files are accepted by the evidence reader; our sample file follows its layout.', 'स्टेशन फ़ाइलें सबूत-रीडर में चलती हैं; नमूना फ़ाइल इसी ढाँचे में है।', used: false),
  Reference('NASA tools', 'Time-Series Analysis of Remotely-Sensed SeaWiFS Chlorophyll in River-Influenced Coastal Regions', 'NASA NTRS 20090042747', 'https://ntrs.nasa.gov/citations/20090042747',
      'Listed challenge resource on building a time series and testing its significance; guided our removal of the seasonal cycle before testing.', 'टाइम-सीरीज़ बनाने और परखने पर चुनौती का सुझाया लेख; जाँच से पहले मौसमी चक्र हटाने में मार्गदर्शक।', used: false),
  // Space agency partners
  Reference('Space agency partners', 'KNMI Climate Explorer', 'Royal Netherlands Meteorological Institute (KNMI)', 'https://climexp.knmi.nl/',
      'Reference tool for climate index series (El Niño, Indian Ocean Dipole) used as "suspects"; its series files are accepted by the evidence reader.', 'जलवायु सूचकांकों (अल नीनो, IOD) का संदर्भ-टूल जो "संदिग्ध" के रूप में परखे जाते हैं; इसकी फ़ाइलें सबूत-रीडर में चलती हैं।', used: false),
  Reference('Space agency partners', 'SWOT mission', 'NASA + CNES, with the Canadian Space Agency (CSA) and UK Space Agency', 'https://www.asc-csa.gc.ca/eng/satellites/swot/',
      'Background for water cases. SWOT began in 2023, too short for a trend test yet - an honest "needs more years" example.', 'पानी वाले केसों की पृष्ठभूमि। SWOT 2023 में शुरू हुआ, रुझान-जाँच के लिए अभी छोटा - "और साल चाहिए" का सच्चा उदाहरण।', used: false),
  Reference('Space agency partners', 'RADARSAT Constellation Mission data', 'Canadian Space Agency (CSA)', 'https://donnees-data.asc-csa.gc.ca/en/dataset/rcm',
      'Listed partner resource (radar images of ice, wetlands, coasts). Not computed with in this version.', 'सूचीबद्ध साझेदार संसाधन (बर्फ़, आर्द्रभूमि, तटों की रडार तस्वीरें)। इस संस्करण में गणना में नहीं।', used: false),
  Reference('Space agency partners', 'Monitoring and protecting our ecosystems from space', 'Canadian Space Agency (CSA)', 'https://www.asc-csa.gc.ca/eng/satellites/everyday-lives/monitoring-and-protecting-our-ecosystems-from-space.asp',
      'Background reading on why ecosystem variables matter.', 'पारिस्थितिकी चरों के महत्व पर पृष्ठभूमि।', used: false),
  Reference('Space agency partners', 'GEO.ca', 'Government of Canada', 'http://geo.ca/', 'Listed partner resource for open geospatial data. Not computed with.', 'खुले भू-डेटा का सूचीबद्ध साझेदार संसाधन। गणना में नहीं।', used: false),
  Reference('Space agency partners', 'Synthetic Aperture Radar Python Tutorial', 'Canadian Space Agency (CSA)', 'https://github.com/asc-csa/Synthetic_Aperture_Radar_Tutorial',
      'Listed partner tutorial. Not used in this version.', 'सूचीबद्ध साझेदार ट्यूटोरियल। इस संस्करण में उपयोग नहीं।', used: false),
  Reference('Space agency partners', 'Bhuvan and MOSDAC', 'Indian Space Research Organisation (ISRO)', 'https://bhuvan.nrsc.gov.in/',
      'India\'s own Earth-observation portals; linked for users who want Indian satellite data for the India cases. Not computed with.', 'भारत के अपने भू-प्रेक्षण पोर्टल; भारत वाले केसों के लिए भारतीय उपग्रह डेटा चाहने वालों हेतु लिंक। गणना में नहीं।', used: false),
  // Methods
  Reference('Methods', 'Statistical test methods to detect trends in time series data', 'S. Kriss, Medium (challenge resource)', 'https://medium.com/@snp.kriss/statistical-test-methods-to-detect-trends-in-time-series-data-b361a0ec530b',
      'The tests shown side by side follow this resource: line fit with t-test, Mann-Kendall, Seasonal Kendall.', 'साथ-साथ दिखाई गई जाँचें इसी संसाधन के अनुसार: t-टेस्ट, मान-केंडल, मौसमी केंडल।'),
  Reference('Methods', 'A Comprehensive Guide to Statistical Significance', 'Statsig (challenge resource)', 'https://www.statsig.com/perspectives/a-comprehensive-guide-to-statistical-significance',
      'Plain-language framing of p-values and confidence intervals.', 'p-मान और विश्वास अंतराल की सरल व्याख्या।', used: false),
  Reference('Methods', 'Mann (1945); Kendall (1975)', 'Econometrica 13; Rank Correlation Methods', 'https://doi.org/10.2307/1907187', 'The Mann-Kendall trend test.', 'मान-केंडल रुझान जाँच।'),
  Reference('Methods', 'Sen (1968)', 'J. Amer. Statist. Assoc. 63', 'https://doi.org/10.1080/01621459.1968.10480934', 'Sen\'s slope: the rate of change.', 'सेन ढलान: बदलाव की दर।'),
  Reference('Methods', 'Hirsch & Slack (1984)', 'Water Resources Research 20', 'https://doi.org/10.1029/WR020i006p00727', 'Seasonal Kendall test.', 'मौसमी केंडल जाँच।'),
  Reference('Methods', 'Santer et al. (2008)', 'Int. J. Climatology 28', 'https://doi.org/10.1002/joc.1756', 'Effective sample size for the t-test when years are not independent.', 'जब साल स्वतंत्र न हों तब t-टेस्ट का प्रभावी नमूना आकार।'),
  Reference('Methods', 'Wilks (2016)', 'Bull. Amer. Meteor. Soc. 97', 'https://doi.org/10.1175/BAMS-D-15-00267.1', 'False-discovery control on maps, so thousands of cells cannot fake significance.', 'नक़्शों पर झूठी खोज नियंत्रण, ताकि हज़ारों खाने मिलकर झूठा महत्व न दिखाएँ।'),
  Reference('Methods', 'Weatherhead et al. (1998)', 'J. Geophys. Res. 103', 'https://doi.org/10.1029/98JD00995', '"Years still needed" to detect a trend.', 'रुझान पकड़ने के लिए "और कितने साल"।'),
  Reference('Methods', 'Pettitt (1979)', 'Applied Statistics 28', 'https://doi.org/10.2307/2346729', 'Change-point test behind the instrument "alibi check".', 'यंत्र के "बहाने की जाँच" के पीछे की परिवर्तन-बिंदु जाँच।'),
  Reference('Methods', 'CUAHSI hydrologic tools', 'Consortium of Universities for the Advancement of Hydrologic Science', 'https://www.cuahsi.org/',
      'Suggested in the challenge; reviewed as a model for plotting hydrology series.', 'चुनौती में सुझाया गया; जल-विज्ञान शृंखला के चित्रण के मॉडल के रूप में देखा गया।', used: false),
  // Software
  Reference('Software', 'Flutter, Firebase (Hosting, Firestore, Auth, AI Logic)', 'Google', 'https://firebase.google.com/', 'App, hosting, cache and the AI explainer.', 'ऐप, होस्टिंग, कैश और एआई व्याख्याकार।'),
  Reference('Software', 'xarray, NumPy, SciPy, pandas, Pillow', 'open source', 'https://xarray.dev/', 'The Python data pipeline.', 'पायथन डेटा पाइपलाइन।'),
  Reference('Software', 'Groq and OpenRouter (back-up AI text)', 'Groq Inc.; OpenRouter Inc.', 'https://console.groq.com/docs/models', 'Back-up language models for the labelled AI notes when Gemini does not answer. Never used for verdicts.', 'जब Gemini जवाब न दे तब लेबल-युक्त एआई नोट्स के लिए बैक-अप मॉडल। फ़ैसलों में कभी नहीं।'),
  Reference('Software', 'BigDataCloud and OpenStreetMap Nominatim', 'BigDataCloud; OpenStreetMap contributors (ODbL)', 'https://www.bigdatacloud.com/free-api/free-reverse-geocode-to-city-api', 'Place names (town, state, country, continent) under the pointer on the map.', 'नक़्शे पर पॉइंटर के नीचे जगह का नाम (क़स्बा, राज्य, देश, महाद्वीप)।'),
  Reference('Software', 'Nunito typeface', 'The Nunito Project Authors (SIL Open Font License 1.1)', 'https://github.com/googlefonts/nunito', 'Rounded heading font, bundled with the app.', 'गोल शीर्षक फ़ॉन्ट, ऐप के साथ शामिल।'),
  Reference('Software', 'Open-Meteo weather API', 'Open-Meteo.com (CC BY 4.0)', 'https://open-meteo.com/', 'Only the "here and now" weather strip. Never used in any trend or verdict.', 'सिर्फ़ "यहाँ और अभी" मौसम पट्टी। किसी रुझान या फ़ैसले में कभी नहीं।'),
  Reference('Software', 'Natural Earth', 'public domain', 'https://www.naturalearthdata.com/', 'Coastlines and city names on the map and globe.', 'नक़्शे और ग्लोब पर तटरेखाएँ और शहरों के नाम।'),
];
