<#
.SYNOPSIS
  Read-only probe comparing WMI invocation styles for hpqBIOSInt128.

.DESCRIPTION
  The tray app currently gets "Invalid method Parameter(s)". This script tries
  four variants and prints the return codes without writing to the firmware
  (Command = 0x01, read only). Run elevated.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Continue'

$source = @'
using System;
using System.Collections.Generic;
using System.Globalization;
using System.Management;

public static class WmiProbe
{
    private static readonly byte[] Signature = { 0x53, 0x45, 0x43, 0x55 };

    public static string RunAll()
    {
        var report = new List<string>();
        ManagementScope scope;
        ManagementClass biosClass;
        ManagementClass inputClass;
        try
        {
            scope = new ManagementScope(@"\\.\root\wmi");
            scope.Connect();
            biosClass = new ManagementClass(scope, new ManagementPath("hpqBIntM"), null);
            biosClass.Get();
            inputClass = new ManagementClass(scope, new ManagementPath("hpqBDataIn"), null);
            inputClass.Get();
        }
        catch (Exception ex)
        {
            return "setup failed: " + ex.Message;
        }

        report.Add("A class/class+Get: " + Try(delegate { return InvokeClass(biosClass, inputClass); }));
        report.Add("B instance params: " + Try(delegate { return InvokeInstance(biosClass, inputClass); }));
        report.Add("C object array: " + Try(delegate { return InvokeArray(biosClass, inputClass); }));
        report.Add("D instance array: " + Try(delegate { return InvokeInstanceArray(biosClass, inputClass); }));
        return string.Join(Environment.NewLine, report.ToArray());
    }

    private static string Try(Func<string> action)
    {
        try { return action(); }
        catch (Exception ex) { return "EX " + ex.GetType().Name + ": " + ex.Message; }
    }

    private static ManagementBaseObject BuildInput(ManagementClass inputClass)
    {
        ManagementBaseObject input = inputClass.CreateInstance();
        input["Command"] = 1u;
        input["CommandType"] = 0x2bu;
        input["Size"] = 4u;
        input["hpqBData"] = new byte[] { 0, 0, 0, 0 };
        input["Sign"] = Signature;
        return input;
    }

    private static string Report(ManagementBaseObject output)
    {
        if (output == null) return "no output object";
        var data = output["OutData"] as ManagementBaseObject;
        if (data == null) return "no OutData";
        var code = Convert.ToUInt32(data["rwReturnCode"], CultureInfo.InvariantCulture);
        var bytes = data["Data"] as byte[];
        var text = "";
        if (bytes != null)
            foreach (var b in bytes) text += b.ToString("X2", CultureInfo.InvariantCulture) + " ";
        return "rc=" + code + " data=[" + text.Trim() + "]";
    }

    private static string InvokeClass(ManagementClass biosClass, ManagementClass inputClass)
    {
        using (var input = BuildInput(inputClass))
        using (var parameters = biosClass.GetMethodParameters("hpqBIOSInt128"))
        {
            parameters["InData"] = input;
            using (var output = biosClass.InvokeMethod("hpqBIOSInt128", parameters, null))
                return Report(output);
        }
    }

    private static string InvokeInstance(ManagementClass biosClass, ManagementClass inputClass)
    {
        foreach (ManagementObject instance in biosClass.GetInstances())
        {
            using (instance)
            using (var input = BuildInput(inputClass))
            using (var parameters = instance.GetMethodParameters("hpqBIOSInt128"))
            {
                parameters["InData"] = input;
                using (var output = instance.InvokeMethod("hpqBIOSInt128", parameters, null))
                    return Report(output);
            }
        }
        return "no instance";
    }

    private static string InvokeArray(ManagementClass biosClass, ManagementClass inputClass)
    {
        using (var input = BuildInput(inputClass))
        {
            var args = new object[] { input, null };
            object result = biosClass.InvokeMethod("hpqBIOSInt128", args);
            return "ret=" + result + " out=" + (args[1] == null ? "null" : Report((ManagementBaseObject)args[1]));
        }
    }

    private static string InvokeInstanceArray(ManagementClass biosClass, ManagementClass inputClass)
    {
        foreach (ManagementObject instance in biosClass.GetInstances())
        {
            using (instance)
            using (var input = BuildInput(inputClass))
            {
                var args = new object[] { input, null };
                object result = instance.InvokeMethod("hpqBIOSInt128", args);
                return "ret=" + result + " out=" + (args[1] == null ? "null" : Report((ManagementBaseObject)args[1]));
            }
        }
        return "no instance";
    }
}
'@

Add-Type -TypeDefinition $source -Language CSharp -ReferencedAssemblies 'System.dll', 'System.Management.dll'
[WmiProbe]::RunAll()
