# Windows Credential Manager helper used by server.js (same entry as the PowerShell server).
# Usage: powershell -File cred.ps1 get|set|del   (for "set" the PAT is read from stdin)
param([string]$Action)
$ErrorActionPreference='Stop'
$target='SprintTimeTracker:AzureDevOpsPAT'
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
switch($Action){
 'get'{$v=[Cred]::Get($target);if($v){[Console]::Out.Write($v)}}
 'set'{$v=[Console]::In.ReadToEnd().Trim();[Cred]::Set($target,$v)}
 'del'{[Cred]::Del($target)}
}
