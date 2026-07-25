/*
 * Copyright (c) 2026 Kevin Hasselquist
 * SPDX-License-Identifier: MIT
 */

#include <QtQml>
#include "mediacache.h"

class UTSlackPlugin : public QQmlExtensionPlugin
{
    Q_OBJECT
    Q_PLUGIN_METADATA(IID QQmlExtensionInterface_iid)

public:
    void registerTypes(const char *uri) override
    {
        Q_ASSERT(QLatin1String(uri) == QLatin1String("UTSlack"));
        qmlRegisterSingletonType<MediaCache>(
            uri, 1, 0, "MediaCache",
            [](QQmlEngine *, QJSEngine *) -> QObject * {
                return new MediaCache;
            });
    }
};

#include "plugin.moc"
