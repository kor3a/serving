"""Error shapes the iOS client understands.

`APIClient.swift` reads `detail` first, then falls back to the first value of
any field-error list, so both DRF conventions render as a usable message.
Status codes it treats specially: 401 (refresh then sign out), 402 (payment
declined), 404 (not found).
"""

from rest_framework import status
from rest_framework.exceptions import APIException
from rest_framework.views import exception_handler as drf_exception_handler


class PaymentDeclined(APIException):
    status_code = status.HTTP_402_PAYMENT_REQUIRED
    default_detail = "Your payment was declined. Try a different method."
    default_code = "payment_declined"


class OrderTransitionError(APIException):
    """The order is not in a state where this action makes sense."""

    status_code = status.HTTP_409_CONFLICT
    default_detail = "This order can no longer be changed."
    default_code = "invalid_transition"


def serving_exception_handler(exc, context):
    response = drf_exception_handler(exc, context)
    if response is None:
        return None

    # Collapse a bare list body into the {"detail": ...} shape.
    if isinstance(response.data, list) and response.data:
        response.data = {"detail": str(response.data[0])}

    return response
