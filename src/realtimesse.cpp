/*
 * Copyright (c) 2026 Kevin Hasselquist
 * SPDX-License-Identifier: MIT
 */

#include "realtimesse.h"

#include <QNetworkRequest>
#include <QUrl>

RealtimeSse::RealtimeSse(QObject *parent)
    : QObject(parent)
    , m_reply(nullptr)
    , m_active(false)
    , m_status(QStringLiteral("disconnected"))
{
}

RealtimeSse::~RealtimeSse()
{
    abortReply();
}

void RealtimeSse::setUrl(const QString &url)
{
    if (m_url == url)
        return;
    m_url = url;
    emit urlChanged();
}

void RealtimeSse::open()
{
    abortReply();
    m_buffer.clear();
    m_dataLines.clear();

    if (m_url.isEmpty()) {
        setLastError(QStringLiteral("No SSE URL"));
        setStatus(QStringLiteral("error"));
        return;
    }

    QUrl qurl(m_url);
    if (!qurl.isValid() || qurl.scheme().isEmpty()) {
        setLastError(QStringLiteral("Invalid SSE URL"));
        setStatus(QStringLiteral("error"));
        return;
    }

    setLastError(QString());
    setStatus(QStringLiteral("connecting"));

    QNetworkRequest req(qurl);
    req.setRawHeader("Accept", "text/event-stream");
    req.setRawHeader("Cache-Control", "no-cache");
#if QT_VERSION >= QT_VERSION_CHECK(5, 9, 0)
    req.setAttribute(QNetworkRequest::RedirectPolicyAttribute,
                     QNetworkRequest::NoLessSafeRedirectPolicy);
#elif QT_VERSION >= QT_VERSION_CHECK(5, 6, 0)
    req.setAttribute(QNetworkRequest::FollowRedirectsAttribute, true);
#endif

    m_reply = m_nam.get(req);
    connect(m_reply, &QNetworkReply::readyRead, this, &RealtimeSse::onReadyRead);
    connect(m_reply, &QNetworkReply::finished, this, &RealtimeSse::onFinished);
    connect(m_reply,
            static_cast<void (QNetworkReply::*)(QNetworkReply::NetworkError)>(&QNetworkReply::error),
            this, &RealtimeSse::onError);
}

void RealtimeSse::close()
{
    abortReply();
    setActive(false);
    setStatus(QStringLiteral("disconnected"));
}

void RealtimeSse::abortReply()
{
    if (!m_reply)
        return;
    QNetworkReply *reply = m_reply;
    m_reply = nullptr;
    reply->disconnect(this);
    reply->abort();
    reply->deleteLater();
}

void RealtimeSse::onReadyRead()
{
    if (!m_reply)
        return;
    if (!m_active) {
        setActive(true);
        setStatus(QStringLiteral("connected"));
        setLastError(QString());
    }
    m_buffer.append(QString::fromUtf8(m_reply->readAll()));
    consumeBuffer();
}

void RealtimeSse::consumeBuffer()
{
    while (true) {
        const int nl = m_buffer.indexOf(QLatin1Char('\n'));
        if (nl < 0)
            break;
        QString line = m_buffer.left(nl);
        m_buffer.remove(0, nl + 1);
        if (line.endsWith(QLatin1Char('\r')))
            line.chop(1);

        if (line.isEmpty()) {
            if (!m_dataLines.isEmpty()) {
                emit eventReceived(m_dataLines);
                m_dataLines.clear();
            }
            continue;
        }
        if (line.startsWith(QLatin1Char(':')))
            continue; // comment / keepalive
        if (line.startsWith(QStringLiteral("data:"))) {
            QString payload = line.mid(5);
            if (payload.startsWith(QLatin1Char(' ')))
                payload = payload.mid(1);
            if (!m_dataLines.isEmpty())
                m_dataLines.append(QLatin1Char('\n'));
            m_dataLines.append(payload);
        }
        // id: / event: / retry: ignored for v1
    }
}

void RealtimeSse::onFinished()
{
    if (m_reply) {
        // Drain any trailing bytes
        m_buffer.append(QString::fromUtf8(m_reply->readAll()));
        consumeBuffer();
        if (!m_dataLines.isEmpty()) {
            emit eventReceived(m_dataLines);
            m_dataLines.clear();
        }

        const int status = m_reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
        if (status && (status < 200 || status >= 300) && m_lastError.isEmpty())
            setLastError(QStringLiteral("HTTP %1").arg(status));

        m_reply->deleteLater();
        m_reply = nullptr;
    }
    setActive(false);
    if (m_status != QStringLiteral("error"))
        setStatus(QStringLiteral("disconnected"));
}

void RealtimeSse::onError(QNetworkReply::NetworkError)
{
    if (!m_reply)
        return;
    // OperationCanceledError from abort() is expected on close/reconnect
    if (m_reply->error() == QNetworkReply::OperationCanceledError)
        return;
    setLastError(m_reply->errorString());
    setStatus(QStringLiteral("error"));
    setActive(false);
}

void RealtimeSse::setStatus(const QString &status)
{
    if (m_status == status)
        return;
    m_status = status;
    emit statusChanged();
}

void RealtimeSse::setActive(bool active)
{
    if (m_active == active)
        return;
    m_active = active;
    emit activeChanged();
}

void RealtimeSse::setLastError(const QString &error)
{
    if (m_lastError == error)
        return;
    m_lastError = error;
    emit lastErrorChanged();
}
