﻿// Copyright 2021 Samsung Electronics Co., Ltd. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

using System;

namespace Tizen.Flutter.Embedding
{
    /// <summary>
    /// Thrown to indicate that a platform interaction failed to find a handling plugin.
    /// </summary>
    public class MissingPluginException : Exception
    {
        /// <summary>
        /// Creates a <see cref="MissingPluginException"/>.
        /// </summary>
        public MissingPluginException() : base()
        {
        }

        /// <summary>
        /// Creates a <see cref="MissingPluginException"/> with a specified error message.
        /// </summary>
        public MissingPluginException(string message) : base(message)
        {
        }
    }
}
