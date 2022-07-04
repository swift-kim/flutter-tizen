﻿// Copyright 2021 Samsung Electronics Co., Ltd. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

using System;
using System.Collections.Generic;
using System.Diagnostics;
using Tizen.Applications;
using static Tizen.Flutter.Embedding.Interop;

namespace Tizen.Flutter.Embedding
{
    /// <summary>
    /// The app base class for headless Flutter execution.
    /// </summary>
    public class FlutterServiceApplication : ServiceApplication, IPluginRegistry
    {
        /// <summary>
        /// The switches to pass to the Flutter engine.
        /// Custom switches may be added before <see cref="OnCreate"/> is called.
        /// </summary>
        protected List<string> EngineArgs { get; } = new List<string>();

        /// <summary>
        /// The optional entrypoint in the Dart project. Defaults to main() if the value is empty.
        /// </summary>
        public string DartEntrypoint { get; set; } = string.Empty;

        /// <summary>
        /// The list of Dart entrypoint arguments.
        /// </summary>
        private List<string> DartEntrypointArgs { get; } = new List<string>();

        /// <summary>
        /// The Flutter engine instance handle.
        /// </summary>
        internal FlutterDesktopEngine Engine { get; private set; } = new FlutterDesktopEngine();

        public override void Run(string[] args)
        {
            // Log any unhandled exception.
            AppDomain.CurrentDomain.UnhandledException += (s, e) =>
            {
                var exception = e.ExceptionObject as Exception;
                TizenLog.Error($"Unhandled exception: {exception}");
            };

            base.Run(args);
        }

        protected override void OnCreate()
        {
            base.OnCreate();

            Utils.ParseEngineArgs(EngineArgs);

            using (var switches = new StringArray(EngineArgs))
            using (var entrypointArgs = new StringArray(DartEntrypointArgs))
            {
                var engineProperties = new FlutterDesktopEngineProperties
                {
                    assets_path = "../res/flutter_assets",
                    icu_data_path = "../res/icudtl.dat",
                    aot_library_path = "../lib/libapp.so",
                    switches = switches.Handle,
                    switches_count = (uint)switches.Length,
                    entrypoint = DartEntrypoint,
                    dart_entrypoint_argc = entrypointArgs.Length,
                    dart_entrypoint_argv = entrypointArgs.Handle,
                };

                Engine = FlutterDesktopEngineCreate(ref engineProperties);
                if (Engine.IsInvalid)
                {
                    throw new Exception("Could not create a Flutter engine.");
                }

                if (!FlutterDesktopEngineRun(Engine))
                {
                    throw new Exception("Could not launch a service application.");
                }
            }
        }

        protected override void OnTerminate()
        {
            base.OnTerminate();

            Debug.Assert(Engine);

            DotnetPluginRegistry.Instance.RemoveAllPlugins();
            FlutterDesktopEngineShutdown(Engine);
        }

        protected override void OnAppControlReceived(AppControlReceivedEventArgs e)
        {
            Debug.Assert(Engine);

            FlutterDesktopEngineNotifyAppControl(Engine, e.ReceivedAppControl.SafeAppControlHandle);
        }

        protected override void OnLowMemory(LowMemoryEventArgs e)
        {
            base.OnLowMemory(e);

            Debug.Assert(Engine);

            FlutterDesktopEngineNotifyLowMemoryWarning(Engine);
        }

        protected override void OnLocaleChanged(LocaleChangedEventArgs e)
        {
            base.OnLocaleChanged(e);

            Debug.Assert(Engine);

            FlutterDesktopEngineNotifyLocaleChange(Engine);
        }

        protected override void OnRegionFormatChanged(RegionFormatChangedEventArgs e)
        {
            base.OnRegionFormatChanged(e);

            Debug.Assert(Engine);

            FlutterDesktopEngineNotifyLocaleChange(Engine);
        }

        /// <summary>
        /// Returns the plugin registrar handle for the plugin with the given name.
        /// The name must be unique across the application.
        /// </summary>
        public FlutterDesktopPluginRegistrar GetRegistrarForPlugin(string pluginName)
        {
            if (Engine)
            {
                return FlutterDesktopEngineGetPluginRegistrar(Engine, pluginName);
            }
            return new FlutterDesktopPluginRegistrar();
        }
    }
}
