# Stands in for the browser helper: registers with the portal, then sends a
# WebAuthn request on the same connection. With --direct, skips the portal and
# calls credentialsd itself, which must be rejected.
import asyncio
import json
import sys

from dbus_next import Message, MessageType, Variant
from dbus_next.aio import MessageBus

PORTAL = "org.freedesktop.portal.Desktop"
PATH = "/org/freedesktop/portal/desktop"
ORIGIN = "https://example.com"
REQUEST = json.dumps(
    {
        "rp": {"id": "example.com", "name": "Example"},
        "user": {"id": "AAAA", "name": "user", "displayName": "user"},
        "challenge": "AAAAAAAAAAAAAAAAAAAAAA",
        "pubKeyCredParams": [{"type": "public-key", "alg": -7}],
    }
)


async def via_portal(bus, app_id):
    reply = await bus.call(
        Message(
            destination=PORTAL,
            path=PATH,
            interface="org.freedesktop.host.portal.Registry",
            member="Register",
            signature="sa{sv}",
            body=[app_id, {}],
        )
    )
    print("register:", "ok" if reply.message_type == MessageType.METHOD_RETURN else "failed")

    # The portal must always reply, even if the registration failed.
    reply = await asyncio.wait_for(
        bus.call(
            Message(
                destination=PORTAL,
                path=PATH,
                interface="org.freedesktop.portal.experimental.Credential",
                member="CreateCredential",
                signature="sssa{sv}",
                body=[
                    "",
                    ORIGIN,
                    "publicKey",
                    {"handle_token": Variant("s", "t1"), "public_key": Variant("s", REQUEST)},
                ],
            )
        ),
        timeout=15,
    )
    assert reply.message_type == MessageType.METHOD_RETURN, reply.body
    print("create: ok")

    # Closing the connection would cancel the request.
    await asyncio.sleep(5)


async def direct(bus):
    reply = await bus.call(
        Message(
            destination="xyz.iinuwa.credentialsd.Credentials",
            path=PATH,
            interface="org.freedesktop.handler.portal.experimental.Credential",
            member="CreateCredential",
            signature="sssa{sv}s",
            body=["", ORIGIN, "publicKey", {"public_key": Variant("s", "{}")}, "org.mozilla.firefox"],
        )
    )
    print("direct:", reply.body)


async def main():
    bus = await MessageBus().connect()
    if sys.argv[1] == "--direct":
        await direct(bus)
    else:
        await via_portal(bus, sys.argv[1])


asyncio.run(main())
