using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;
public static class ChestIdentity {
    [StructLayout(LayoutKind.Sequential)]
    struct Info {
        public uint Attributes;
        public System.Runtime.InteropServices.ComTypes.FILETIME Created, Accessed, Written;
        public uint Volume, SizeHigh, SizeLow, Links, IndexHigh, IndexLow;
    }
    [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
    static extern SafeFileHandle CreateFile(string path,uint access,uint share,IntPtr security,uint creation,uint flags,IntPtr template);
    [DllImport("kernel32.dll",SetLastError=true)]
    static extern bool GetFileInformationByHandle(SafeFileHandle file,out Info info);
    public static string Read(string path) {
        using(var h=CreateFile(path,0,7,IntPtr.Zero,3,0x02200000,IntPtr.Zero)){
            if(h.IsInvalid) throw new Win32Exception();
            Info i; if(!GetFileInformationByHandle(h,out i)) throw new Win32Exception();
            return String.Format("{0:X8}-{1:X8}{2:X8}-{3:X8}{4:X8}",i.Volume,i.IndexHigh,i.IndexLow,i.Created.dwHighDateTime,i.Created.dwLowDateTime);
        }
    }
}
