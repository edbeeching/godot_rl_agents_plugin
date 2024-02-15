using Godot;
using Microsoft.ML.OnnxRuntime;
using Microsoft.ML.OnnxRuntime.Tensors;
using System.Collections.Generic;
using System.Linq;

namespace GodotONNX
{
    /// <include file='docs/ONNXInference.xml' path='docs/members[@name="ONNXInference"]/ONNXInference/*'/>
    public partial class ONNXInference : GodotObject
    {

        private InferenceSession session;
        /// <summary>
        /// Path to the ONNX model. Use Initialize to change it. 
        /// </summary>
        private string modelPath;
        private int batchSize;

        private SessionOptions SessionOpt;

        //init function
        /// <include file='docs/ONNXInference.xml' path='docs/members[@name="ONNXInference"]/Initialize/*'/>
        public void Initialize(string Path, int BatchSize)
        {
            modelPath = Path;
            batchSize = BatchSize;
            SessionOpt = SessionConfigurator.MakeConfiguredSessionOptions();
            session = LoadModel(modelPath);

        }
        /// <include file='docs/ONNXInference.xml' path='docs/members[@name="ONNXInference"]/Run/*'/>
        public Godot.Collections.Dictionary<string, Godot.Collections.Array> RunInference(Godot.Collections.Array<float> obs, int state_ins)
        {
            //Current model: Any (Godot Rl Agents)
            //Expects a tensor of shape [batch_size, input_size] type float named obs and a tensor of shape [batch_size] type float named state_ins

            //Fill the input tensors
            // create span from inputSize
            var span = new float[obs.Count]; //There's probably a better way to do this
            for (int i = 0; i < obs.Count; i++)
            {
                span[i] = obs[i];
            }

            IReadOnlyCollection<NamedOnnxValue> inputs = new List<NamedOnnxValue>
            {
            NamedOnnxValue.CreateFromTensor("obs", new DenseTensor<float>(span, new int[] { batchSize, obs.Count })),
            NamedOnnxValue.CreateFromTensor("state_ins", new DenseTensor<float>(new float[] { state_ins }, new int[] { batchSize }))
            };
            IReadOnlyCollection<string> outputNames = new List<string> { "output", "state_outs" }; //ONNX is sensible to these names, as well as the input names

            IDisposableReadOnlyCollection<DisposableNamedOnnxValue> results;
            //We do not use "using" here so we get a better exception explaination later
            try
            {
                results = session.Run(inputs, outputNames);
            }
            catch (OnnxRuntimeException e)
            {
                //This error usually means that the model is not compatible with the input, beacause of the input shape (size)
                GD.Print("Error at inference: ", e);
                return null;
            }
            //Can't convert IEnumerable<float> to Variant, so we have to convert it to an array or something
            Godot.Collections.Dictionary<string, Godot.Collections.Array> output = new();
            DisposableNamedOnnxValue output1 = results.First();
            DisposableNamedOnnxValue output2 = results.Last();

            // Output1 array may contains longs if only discrete actions are used or floats otherwise
            Godot.Collections.Array output1Array = new();
            Godot.Collections.Array output2Array = new();

            // SB3 exported model will send float actions if continuous actions are used in the environment
            // (also the case with mixed actions)
            if (output1.ElementType == TensorElementType.Float)
            {
                foreach (float f in output1.AsEnumerable<float>())
                {
                    output1Array.Add(f);
                }
            }
            // SB3 exported model will send int64 actions if only discrete actions are used in the environment
            else if (output1.ElementType == TensorElementType.Int64)
            {
                foreach (long l in output1.AsEnumerable<long>())
                {
                    output1Array.Add(l);
                }
            }

            foreach (float f in output2.AsEnumerable<float>())
            {
                output2Array.Add(f);
            }

            output.Add(output1.Name, output1Array);
            output.Add(output2.Name, output2Array);

            //Output is a dictionary of arrays, ex: { "output" : [0.1, 0.2, 0.3, 0.4, ...], "state_outs" : [0.5, ...]}
            results.Dispose();
            return output;
        }
        /// <include file='docs/ONNXInference.xml' path='docs/members[@name="ONNXInference"]/Load/*'/>
        public InferenceSession LoadModel(string Path)
        {
            using FileAccess file = FileAccess.Open(Path, FileAccess.ModeFlags.Read);
            byte[] model = file.GetBuffer((int)file.GetLength());
            //file.Close(); file.Dispose(); //Close the file, then dispose the reference.
            return new InferenceSession(model, SessionOpt); //Load the model
        }
        public void FreeDisposables()
        {
            session.Dispose();
            SessionOpt.Dispose();
        }
    }
}
