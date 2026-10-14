import pathlib, tempfile, json, subprocess, os, shutil
core=pathlib.Path(__file__).resolve().parents[2]
msg=core.parent/'jido_messaging'
script=core/'integration/scripts/audit_api_exports.exs'
checks=[]
with tempfile.TemporaryDirectory(prefix='jido-api-audit-') as folder:
 folder=pathlib.Path(folder)
 for name in ['api-map','catalog','version-matrix','new-major-core-api','core-retired-modules']:
  shutil.copy(core/'docs/migration'/f'{name}.json',folder/f'{name}.json')
 def run(name,phase,manifest):
  out=folder/f'{name}-result.json'
  result=subprocess.run(['mix','run','--no-start',str(script),'--phase',phase,'--manifest',str(manifest),'--output',str(out)],cwd=msg,env=os.environ,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True)
  if result.returncode!=1 or not out.is_file():
   print(result.stdout); raise AssertionError((name,result.returncode))
  return json.loads(out.read_text())
 result=run('missing-applications','G7',core/'docs/migration/version-matrix.json')
 missing=[r['package'] for r in result['failures'] if r['failure']=='required_application_not_loaded']
 assert len(missing)==8, missing
 checks.append({'case':'all eight adapters must be loaded for G7','state':'pass','missing_applications':missing})
 for name in ['api-map','new-major-core-api']:
  path=folder/f'{name}.json'; data=json.loads(path.read_text())
  data['exports']=[r for r in data['exports'] if not (r['module']=='Jido.Messaging' and r['function']=='execute' and r['arity']==3)]
  path.write_text(json.dumps(data))
 result=run('unmapped-entry','G3',folder/'version-matrix.json')
 assert any(r.get('module')=='Jido.Messaging' and r.get('function')=='execute' and r.get('arity')==3 and r['failure']=='unmapped_export' for r in result['failures'])
 checks.append({'case':'unmapped compiled execute/3 fails the audit','state':'pass'})
 # Restore the map, then prove a retired declaration cannot be treated as an active mapping.
 shutil.copy(core/'docs/migration/api-map.json',folder/'api-map.json')
 path=folder/'api-map.json'; data=json.loads(path.read_text())
 for row in data['exports']:
  if row['module']=='Jido.Messaging' and row['function']=='execute' and row['arity']==3:
   row['implementation_state']='retired'
 path.write_text(json.dumps(data))
 result=run('retired-entry','G3',folder/'version-matrix.json')
 assert any(r.get('module')=='Jido.Messaging' and r.get('function')=='execute' and r.get('arity')==3 and r['failure']=='retired_export' for r in result['failures'])
 checks.append({'case':'a retired compiled communication export fails the audit','state':'pass'})
 shutil.copy(core/'docs/migration/api-map.json',folder/'api-map.json')
 path=folder/'version-matrix.json'; data=json.loads(path.read_text())
 data['packages']=[r for r in data['packages'] if r['package']!='jido_messaging']
 path.write_text(json.dumps(data))
 result=run('missing-package','G3',folder/'version-matrix.json')
 assert any(r['failure']=='required_package_row_missing' for r in result['failures'])
 checks.append({'case':'a missing required package row fails the audit','state':'pass'})
print(json.dumps({'state':'pass','checks':checks},indent=2))
