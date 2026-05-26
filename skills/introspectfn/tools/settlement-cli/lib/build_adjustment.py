#!/usr/bin/env python3
"""Build revenue adjustment report from POS and cancelled order data.

Usage: build_adjustment.py <pos_orders.json> <cancelled.json> --partner <p> --venue <v> --from <d> --to <d>
       build_adjustment.py <pos_daily.json> <cancelled.json> --partner <p> --venue <v> --from <d> --to <d> --fuzzy
"""

import argparse
import json
import sys
from collections import defaultdict


def adjust_foodora(pos_orders, cancelled, venue, from_date, to_date):
    cancelled_amounts = defaultdict(list)
    for o in cancelled:
        date = (o.get("order_received_at") or "")[:10]
        amount = float(o.get("subtotal", 0) or 0)
        cancelled_amounts[date].append({
            "order_id": o.get("order_id"),
            "amount": amount,
            "reason": o.get("cancellation_reason", ""),
            "owner": o.get("cancellation_owner", ""),
        })

    pos_daily = defaultdict(lambda: {"count": 0, "total": 0})
    for o in pos_orders:
        date = (o.get("date") or "")[:10]
        amount = float(o.get("amount_after_discounts_sek", 0) or 0)
        pos_daily[date]["count"] += 1
        pos_daily[date]["total"] += amount

    adjustments = []
    total_adjustment = 0

    for date in sorted(cancelled_amounts.keys()):
        orders = cancelled_amounts[date]
        day_total = sum(o["amount"] for o in orders)
        total_adjustment += day_total
        adjustments.append({
            "date": date,
            "cancelled_orders": len(orders),
            "adjustment_amount": round(day_total, 2),
            "orders": orders,
            "pos_orders_that_day": pos_daily.get(date, {}).get("count", 0),
            "pos_total_that_day": round(pos_daily.get(date, {}).get("total", 0), 2),
        })

    return {
        "partner": "foodora",
        "venue": venue,
        "period": {"from": from_date, "to": to_date},
        "match_method": "exact_order_id",
        "total_cancelled_orders": sum(len(a["orders"]) for a in adjustments),
        "total_adjustment_amount": round(total_adjustment, 2),
        "days_with_adjustments": len(adjustments),
        "adjustments": adjustments,
    }


def adjust_fuzzy(pos_daily_data, cancelled, partner, venue, from_date, to_date):
    cancelled_daily = defaultdict(lambda: {"count": 0, "total": 0, "orders": []})
    for o in cancelled:
        date = (o.get("created_time_utc") or "")[:10]
        amount = float(o.get("payment_amount", 0) or o.get("subtotal", 0) or 0)
        cancelled_daily[date]["count"] += 1
        cancelled_daily[date]["total"] += amount
        cancelled_daily[date]["orders"].append({
            "order_id": o.get("channel_order_id", o.get("order_id", "")),
            "amount": amount,
            "status": o.get("status", ""),
        })

    pos_by_date = {}
    for row in pos_daily_data:
        date = row.get("order_date", "")
        pos_by_date[date] = {
            "count": int(row.get("order_count", 0)),
            "total": float(row.get("total_amount_sek", 0)),
        }

    adjustments = []
    total_adjustment = 0

    all_dates = sorted(set(list(cancelled_daily.keys()) + list(pos_by_date.keys())))
    for date in all_dates:
        c = cancelled_daily.get(date, {"count": 0, "total": 0, "orders": []})
        p = pos_by_date.get(date, {"count": 0, "total": 0})

        if c["count"] > 0:
            adj_amount = round(c["total"], 2)
            total_adjustment += adj_amount
            adjustments.append({
                "date": date,
                "cancelled_orders": c["count"],
                "adjustment_amount": adj_amount,
                "pos_orders": p["count"],
                "pos_total": round(p["total"], 2),
                "difference": round(p["total"] - c["total"], 2) if p["total"] > 0 else None,
                "cancelled_order_details": c["orders"],
            })

    return {
        "partner": partner,
        "venue": venue,
        "period": {"from": from_date, "to": to_date},
        "match_method": "fuzzy_daily_totals",
        "total_cancelled_orders": sum(a["cancelled_orders"] for a in adjustments),
        "total_adjustment_amount": round(total_adjustment, 2),
        "days_with_adjustments": len(adjustments),
        "adjustments": adjustments,
    }


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("pos_file")
    parser.add_argument("cancelled_file")
    parser.add_argument("--partner", required=True)
    parser.add_argument("--venue", default="")
    parser.add_argument("--from-date", dest="from_date", required=True)
    parser.add_argument("--to-date", dest="to_date", required=True)
    parser.add_argument("--fuzzy", action="store_true")
    args = parser.parse_args()

    with open(args.pos_file) as f:
        pos_data = json.load(f)
    with open(args.cancelled_file) as f:
        cancelled = json.load(f)

    if args.partner == "foodora" and not args.fuzzy:
        result = adjust_foodora(pos_data, cancelled, args.venue, args.from_date, args.to_date)
    else:
        result = adjust_fuzzy(pos_data, cancelled, args.partner, args.venue, args.from_date, args.to_date)

    print(json.dumps(result, indent=2, ensure_ascii=False))


if __name__ == "__main__":
    main()
