using System;
using Tizen.NUI;
using Tizen.NUI.BaseComponents;

namespace Tizen.Flutter.Embedding
{
    public class NUIFlutterView : ImageView, IPluginRegistry
    {
        public FlutterDesktopPluginRegistrar GetRegistrarForPlugin(string pluginName)
        {
            Console.WriteLine(typeof(NativeImageQueue));
            return new FlutterDesktopPluginRegistrar();
        }
    }
}
