/*
 * Copyright (c) 2026 Kevin Hasselquist
 * SPDX-License-Identifier: MIT
 */

#include "realtimesocket.h"

RealtimeSocket::RealtimeSocket(QObject *parent)
    : QObject(parent)
    , m_active(false)
    , m_status(QStringLiteral("disconnected"))
{
    connect(&m_socket, &QWebSocket::connected,
            this, &RealtimeSocket::onConnected);
    connect(&m_socket, &QWebSocket::disconnected,
            this, &RealtimeSocket::onDisconnected);
    connect(&m_socket, &QWebSocket::textMessageReceived,
            this, &RealtimeSocket::onTextMessageReceived);
    connect(&m_socket,
            static_cast<void (QWebSocket::*)(QAbstractSocket::SocketError)>(&QWebSocket::error),
            this, &RealtimeSocket::onError);
}

void RealtimeSocket::setUrl(const QString &url)
{
    if (m_url == url)
        return;
    m_url = url;
    emit urlChanged();
}

void RealtimeSocket::open()
{
    if (m_url.isEmpty()) {
        setLastError(QStringLiteral("No WebSocket URL"));
        setStatus(QStringLiteral("error"));
        return;
    }
    setLastError(QString());
    setStatus(QStringLiteral("connecting"));
    m_socket.open(QUrl(m_url));
}

void RealtimeSocket::close()
{
    if (m_socket.state() == QAbstractSocket::UnconnectedState) {
        setActive(false);
        setStatus(QStringLiteral("disconnected"));
        return;
    }
    m_socket.close();
}

void RealtimeSocket::sendText(const QString &text)
{
    if (m_socket.state() != QAbstractSocket::ConnectedState)
        return;
    m_socket.sendTextMessage(text);
}

void RealtimeSocket::onConnected()
{
    setActive(true);
    setStatus(QStringLiteral("connected"));
    setLastError(QString());
}

void RealtimeSocket::onDisconnected()
{
    setActive(false);
    if (m_status != QStringLiteral("error"))
        setStatus(QStringLiteral("disconnected"));
}

void RealtimeSocket::onTextMessageReceived(const QString &message)
{
    emit textReceived(message);
}

void RealtimeSocket::onError(QAbstractSocket::SocketError)
{
    setLastError(m_socket.errorString());
    setStatus(QStringLiteral("error"));
    setActive(false);
}

void RealtimeSocket::setStatus(const QString &status)
{
    if (m_status == status)
        return;
    m_status = status;
    emit statusChanged();
}

void RealtimeSocket::setActive(bool active)
{
    if (m_active == active)
        return;
    m_active = active;
    emit activeChanged();
}

void RealtimeSocket::setLastError(const QString &error)
{
    if (m_lastError == error)
        return;
    m_lastError = error;
    emit lastErrorChanged();
}
