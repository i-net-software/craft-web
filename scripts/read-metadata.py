"""Read Maven Central versions and its UTC publication timestamp; malformed data fails closed."""
import datetime
import json
import sys
import xml.etree.ElementTree as ET

metadata = ET.parse(sys.argv[1]).getroot()
versions = metadata.findall("./versioning/versions/version")
updated = metadata.findtext("./versioning/lastUpdated")
if not versions or not updated:
    raise ValueError("Incomplete Maven Central metadata")
timestamp = datetime.datetime.strptime(updated, "%Y%m%d%H%M%S").replace(
    tzinfo=datetime.timezone.utc
).timestamp()
print(json.dumps({"versions": [v.text for v in versions], "updated": int(timestamp)}))
