$ErrorActionPreference='Stop'
$dir=$PSScriptRoot;$data=Join-Path $env:APPDATA 'SprintTimeTracker';New-Item -ItemType Directory -Force $data|Out-Null
$file=Join-Path $data 'data.json';$target='SprintTimeTracker:AzureDevOpsPAT'
$port=8787;$token=[guid]::NewGuid().ToString('N')
Add-Type -AssemblyName System.Net.Http
Add-Type -TypeDefinition @'
using System;using System.Runtime.InteropServices;using System.Text;
public static class Cred{
 [StructLayout(LayoutKind.Sequential,CharSet=CharSet.Unicode)]
 struct CREDENTIAL{public int Flags;public int Type;public string TargetName;public string Comment;public long LastWritten;public int BlobSize;public IntPtr Blob;public int Persist;public int AttrCount;public IntPtr Attrs;public string Alias;public string User;}
 [DllImport("advapi32.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern bool CredWrite(ref CREDENTIAL c,int f);
 [DllImport("advapi32.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern bool CredRead(string t,int type,int f,out IntPtr p);
 [DllImport("advapi32.dll")] static extern void CredFree(IntPtr p);
 [DllImport("advapi32.dll",CharSet=CharSet.Unicode)] static extern bool CredDelete(string t,int type,int f);
 public static void Set(string t,string v){var b=Encoding.Unicode.GetBytes(v);var h=Marshal.AllocHGlobal(b.Length);Marshal.Copy(b,0,h,b.Length);var c=new CREDENTIAL{Type=1,TargetName=t,Blob=h,BlobSize=b.Length,Persist=2,User="pat"};try{if(!CredWrite(ref c,0))throw new Exception("CredWrite failed");}finally{Marshal.FreeHGlobal(h);}}
 public static string Get(string t){IntPtr p;if(!CredRead(t,1,0,out p))return null;try{var c=(CREDENTIAL)Marshal.PtrToStructure(p,typeof(CREDENTIAL));return Marshal.PtrToStringUni(c.Blob,c.BlobSize/2);}finally{CredFree(p);}}
 public static void Del(string t){CredDelete(t,1,0);}
}
'@
$http=New-Object Net.Http.HttpClient
$L=New-Object Net.HttpListener;$L.Prefixes.Add("http://localhost:$port/")
try{$L.Start()}catch{Write-Host "Could not start on port $port. Is it already running?";Read-Host 'Press Enter to close';exit 1}
Write-Host "Sprint Time Tracker is running at http://localhost:$port/  (close this window to stop)"
Start-Process "http://localhost:$port/"
function Txt($s){[Text.Encoding]::UTF8.GetBytes($s)}
function Send($r,$code,$bytes,$type){$r.StatusCode=$code;$r.ContentType=$type;$r.ContentLength64=$bytes.Length;$r.OutputStream.Write($bytes,0,$bytes.Length)}
while($L.IsListening){
 $c=$L.GetContext();$q=$c.Request;$r=$c.Response
 try{
  $p=$q.Url.AbsolutePath
  if($p -eq '/'){
   $html=(Get-Content (Join-Path $dir 'index.html') -Raw -Encoding UTF8).Replace('__TOKEN__',$token)
   Send $r 200 (Txt $html) 'text/html; charset=utf-8'
  }elseif($p.StartsWith('/api/')){
   if($q.Headers['X-Token'] -ne $token){Send $r 403 (Txt '{"message":"forbidden"}') 'application/json';continue}
   $body='';if($q.HasEntityBody){$sr=New-Object IO.StreamReader($q.InputStream,[Text.Encoding]::UTF8);$body=$sr.ReadToEnd()}
   if($p -eq '/api/state'){
    if($q.HttpMethod -eq 'PUT'){[IO.File]::WriteAllText($file,$body,(New-Object Text.UTF8Encoding $false));Send $r 200 (Txt '{"ok":true}') 'application/json'}
    else{$t='{}';if(Test-Path $file){$t=[IO.File]::ReadAllText($file)};Send $r 200 (Txt $t) 'application/json; charset=utf-8'}
   }elseif($p -eq '/api/pat'){
    if($q.HttpMethod -eq 'POST'){[Cred]::Set($target,(ConvertFrom-Json $body).pat)}elseif($q.HttpMethod -eq 'DELETE'){[Cred]::Del($target)}
    Send $r 200 (Txt (@{has=[bool][Cred]::Get($target)}|ConvertTo-Json -Compress)) 'application/json'
   }elseif($p.StartsWith('/api/az/')){
    if($q.HttpMethod -notin 'GET','POST','PATCH'){Send $r 405 (Txt '{"message":"method not allowed"}') 'application/json';continue}
    $pat=[Cred]::Get($target);if(!$pat){Send $r 401 (Txt '{"message":"No PAT stored"}') 'application/json';continue}
    $m=[Net.Http.HttpRequestMessage]::new([Net.Http.HttpMethod]::new($q.HttpMethod),('https://dev.azure.com/'+$q.RawUrl.Substring(8)))
    $m.Headers.Authorization=[Net.Http.Headers.AuthenticationHeaderValue]::new('Basic',[Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":$pat")))
    if($body){$ct=$q.ContentType;if(!$ct){$ct='application/json'};$m.Content=[Net.Http.StringContent]::new($body,[Text.Encoding]::UTF8,$ct.Split(';')[0])}
    $resp=$http.SendAsync($m).Result;$bytes=$resp.Content.ReadAsByteArrayAsync().Result
    Send $r ([int]$resp.StatusCode) $bytes 'application/json; charset=utf-8'
   }else{Send $r 404 (Txt '{"message":"not found"}') 'application/json'}
  }else{Send $r 404 (Txt 'Not found') 'text/plain'}
 }catch{try{Send $r 500 (Txt ('{"message":"'+($_.Exception.Message -replace '["\r\n\\]',' ')+'"}')) 'application/json'}catch{}}
 finally{$r.Close()}
}
