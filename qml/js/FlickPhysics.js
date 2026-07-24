/*
 * Copyright (C) 2026  Kevin
 *
 * Flickable / ListView kinetic scroll defaults for Ubuntu Touch.
 * Platform defaults often cap maximumFlickVelocity so every release
 * coasts at roughly the same speed; scale with grid units so swipe
 * velocity is preserved on high-DPI screens.
 */
.pragma library

function configure(flickable, gridUnit) {
    if (!flickable || !gridUnit)
        return
    // Reference: 8px per gu (laptop); phones use a larger gridUnit.
    flickable.maximumFlickVelocity = 4500 * gridUnit / 8
    flickable.flickDeceleration = 1500 * gridUnit / 8
}
