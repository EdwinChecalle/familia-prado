"""Temporary iOS local networking exception; enable only for private development."""
from pathlib import Path
import plistlib
root=Path(__file__).resolve().parent.parent
path=root/'mobile'/'ios'/'Runner'/'Info.plist'
if not path.exists():
    raise SystemExit('Primero ejecuta flutter create --platforms=ios . desde mobile/')
with path.open('rb') as f: data=plistlib.load(f)
ats=data.setdefault('NSAppTransportSecurity', {})
ats['NSAllowsLocalNetworking']=True
with path.open('wb') as f: plistlib.dump(data,f)
print('Configuración local de iOS habilitada para pruebas. Para producción usa HTTPS.')
