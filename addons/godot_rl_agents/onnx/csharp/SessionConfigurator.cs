using Godot;
using Microsoft.ML.OnnxRuntime;

namespace GodotONNX
{
    /// <include file='docs/SessionConfigurator.xml' path='docs/members[@name="SessionConfigurator"]/SessionConfigurator/*'/>

    public static class SessionConfigurator
    {
        public enum ComputeName
        {
            CUDA,
            ROCm,
            DirectML,
            CoreML,
            CPU
        }

        private static SessionOptions options = new SessionOptions();

        /// <include file='docs/SessionConfigurator.xml' path='docs/members[@name="SessionConfigurator"]/GetSessionOptions/*'/>
        public static SessionOptions GetSessionOptions()
        {
            options.LogSeverityLevel = OrtLoggingLevel.ORT_LOGGING_LEVEL_WARNING;
            // see warnings
            SystemCheck();
            return options;
        }

        /// <include file='docs/SessionConfigurator.xml' path='docs/members[@name="SessionConfigurator"]/SystemCheck/*'/>
        static public void SystemCheck()
        {
            //Most code for this function is verbose only, the only reason it exists is to track
            //implementation progress of the different compute APIs.

            //December 2022: CUDA is not working. 

            string OSName = OS.GetName(); //Get OS Name

            //ComputeName ComputeAPI = ComputeCheck(); //Get Compute API
            //                                         //TODO: Get CPU architecture
            
            //Linux can use OpenVINO (C#) on x64 and ROCm on x86 (GDNative/C++)
            //Windows can use OpenVINO (C#) on x64
            //TODO: try TensorRT instead of CUDA
            //TODO: Use OpenVINO for Intel Graphics

            // Temporarily using CPU on all platforms to avoid errors detected with DML
            ComputeName ComputeAPI = ComputeName.CPU;

            //match OS and Compute API
            GD.Print($"OS: {OSName} Compute API: {ComputeAPI}");

            options.AppendExecutionProvider_CPU(0);

            /*
            switch (OSName)
            {
                case "Windows": //Can use CUDA, DirectML
                    if (ComputeAPI is ComputeName.CUDA)
                    {
                        //CUDA 
                        //options.AppendExecutionProvider_CUDA(0);
                        //options.AppendExecutionProvider_DML(0);
                    }
                    else if (ComputeAPI is ComputeName.DirectML)
                    {
                        //DirectML
                        //options.AppendExecutionProvider_DML(0);
                    }
                    break;
                case "X11": //Can use CUDA, ROCm
                    if (ComputeAPI is ComputeName.CUDA)
                    {
                        //CUDA
                        //options.AppendExecutionProvider_CUDA(0);
                    }
                    if (ComputeAPI is ComputeName.ROCm)
                    {
                        //ROCm, only works on x86 
                        //Research indicates that this has to be compiled as a GDNative plugin
                        //GD.Print("ROCm not supported yet, using CPU.");
                        //options.AppendExecutionProvider_CPU(0);
                    }
                    break;
                case "macOS": //Can use CoreML
                    if (ComputeAPI is ComputeName.CoreML)
                    { //CoreML
                      //TODO: Needs testing
                        //options.AppendExecutionProvider_CoreML(0);
                        //CoreML on ARM64, out of the box, on x64 needs .tar file from GitHub
                    }
                    break;
                default:
                    GD.Print("OS not Supported.");
                    break;
            }
            */
        }
        

        /// <include file='docs/SessionConfigurator.xml' path='docs/members[@name="SessionConfigurator"]/ComputeCheck/*'/>
        public static ComputeName ComputeCheck()
        {
            string adapterName = Godot.RenderingServer.GetVideoAdapterName();
            //string adapterVendor = Godot.RenderingServer.GetVideoAdapterVendor();
            adapterName = adapterName.ToUpper(new System.Globalization.CultureInfo(""));
            //TODO: GPU vendors for MacOS, what do they even use these days?
          
            if (adapterName.Contains("INTEL"))
            {
                return ComputeName.DirectML;
            }
            if (adapterName.Contains("AMD") || adapterName.Contains("RADEON"))
            {
                return ComputeName.DirectML;
            }
            if (adapterName.Contains("NVIDIA"))
            {
                return ComputeName.CUDA;
            }

            GD.Print("Graphics Card not recognized."); //Should use CPU
            return ComputeName.CPU;
        }
    }
}