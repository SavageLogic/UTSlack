/*
 * Copyright (c) 2026 Kevin Hasselquist
 * SPDX-License-Identifier: MIT
 *
 * HTTP helpers that need a reliable Authorization header (QML XHR often drops it).
 */

#ifndef SLACKHTTP_H
#define SLACKHTTP_H

#include <QObject>
#include <QString>
#include <QNetworkAccessManager>
#include <QNetworkReply>

class SlackHttp : public QObject
{
    Q_OBJECT

public:
    explicit SlackHttp(QObject *parent = nullptr);

    // apps.connections.open — requires Bearer xapp- in Authorization only (not body).
    Q_INVOKABLE void appsConnectionsOpen(const QString &appToken);

signals:
    void appsConnectionsOpenFinished(bool ok, const QString &url, const QString &error);

private slots:
    void onConnectionsOpenFinished();

private:
    QNetworkAccessManager m_nam;
    QNetworkReply *m_openReply;
};

#endif
