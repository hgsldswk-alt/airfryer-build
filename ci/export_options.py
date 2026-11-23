"""Render manual signing options for the app and WidgetKit extension."""
import os
from pathlib import Path
import plistlib
import sys

data = plistlib.loads(Path(__file__).with_name("ExportOptions.plist").read_bytes())
app = os.environ.get("APP_ID", "com.hgsldswk.airfryercheatsheet")
widget = os.environ.get("WIDGET_ID") or app + ".widget"
data["teamID"] = os.environ["TEAM_ID"]
data["provisioningProfiles"] = {
    app: os.environ.get("APP_PROFILE", "AirFryerSheet AppStore"),
    widget: os.environ.get("WIDGET_PROFILE", "AirFryerSheet Widget AppStore"),
}
sys.stdout.buffer.write(plistlib.dumps(data))
