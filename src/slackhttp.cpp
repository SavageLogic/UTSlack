/*
 * Copyright (c) 2026 Kevin Hasselquist
 * SPDX-License-Identifier: MIT
 */

#include "slackhttp.h"

#include <QJsonDocument>
#include <QJsonObject>
#include <QNetworkRequest>
#include <QUrl>

SlackHttp::SlackHttp(QObject *parent)
    : QObject(parent)
    , m_openReply(nullptr)
{
}

void SlackHttp::appsConnectionsOpen(const QString &appToken)
{
    if (m_openReply) {
        m_openReply->disconnect(this);
        m_openReply->abort();
        m_openReply->deleteLater();
        m_openReply = nullptr;
    }

    QString token = appToken.trimmed();
    // Strip BOM / zero-width that break Slack auth (mirror JS sanitize)
    token.remove(QChar(0xFEFF));
    token.remove(QChar(0x200B));
    token.remove(QChar(0x200C));
    token.remove(QChar(0x200D));
    token.remove(QLatin1Char(' '));
    token.remove(QLatin1Char('\n'));
    token.remove(QLatin1Char('\r'));
    token.remove(QLatin1Char('\t'));

    if (token.isEmpty() || !token.startsWith(QStringLiteral("xapp-"))) {
        emit appsConnectionsOpenFinished(false, QString(),
            QStringLiteral("App-level token must start with xapp-"));
        return;
    }

    QNetworkRequest req(QUrl(QStringLiteral("https://slack.com/api/apps.connections.open")));
    req.setHeader(QNetworkRequest::ContentTypeHeader,
                  QStringLiteral("application/x-www-form-urlencoded"));
    req.setRawHeader("Authorization",
                     QByteArray("Bearer ") + token.toUtf8());

    // Empty body — Slack requires Authorization header for this method;
    // a token= body param alone returns invalid_auth.
    m_openReply = m_nam.post(req, QByteArray());
    connect(m_openReply, &QNetworkReply::finished,
            this, &SlackHttp::onConnectionsOpenFinished);
}

void SlackHttp::onConnectionsOpenFinished()
{
    QNetworkReply *reply = m_openReply;
    m_openReply = nullptr;
    if (!reply) {
        emit appsConnectionsOpenFinished(false, QString(), QStringLiteral("No reply"));
        return;
    }
    reply->deleteLater();

    if (reply->error() != QNetworkReply::NoError
            && reply->error() != QNetworkReply::UnknownContentError) {
        // Slack still returns JSON with HTTP 200 for API errors; network failures here
        if (reply->error() == QNetworkReply::OperationCanceledError)
            return;
        // Fall through to parse body if any; otherwise report network error
        if (reply->bytesAvailable() == 0 && reply->size() == 0) {
            emit appsConnectionsOpenFinished(false, QString(), reply->errorString());
            return;
        }
    }

    const QByteArray raw = reply->readAll();
    QJsonParseError err;
    const QJsonDocument doc = QJsonDocument::fromJson(raw, &err);
    if (err.error != QJsonParseError::NoError || !doc.isObject()) {
        emit appsConnectionsOpenFinished(false, QString(),
            QStringLiteral("Failed to parse apps.connections.open response"));
        return;
    }

    const QJsonObject obj = doc.object();
    if (!obj.value(QStringLiteral("ok")).toBool()) {
        const QString apiErr = obj.value(QStringLiteral("error")).toString();
        emit appsConnectionsOpenFinished(false, QString(),
            apiErr.isEmpty() ? QStringLiteral("apps.connections.open failed") : apiErr);
        return;
    }

    const QString url = obj.value(QStringLiteral("url")).toString();
    if (url.isEmpty()) {
        emit appsConnectionsOpenFinished(false, QString(),
            QStringLiteral("No WebSocket URL in response"));
        return;
    }

    emit appsConnectionsOpenFinished(true, url, QString());
}
