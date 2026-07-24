from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import re
import sys
from collections import OrderedDict
from datetime import date, datetime
from pathlib import Path
from typing import Any


DEFAULT_SOURCE = Path(r"Z:\TO承憲\ERP\IACF")
PROJECT_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_DASHBOARD = (
    PROJECT_ROOT / "public" / "phoenixes-film-inventory" / "dashboard-data.js"
)
BASE_BUILD_SCRIPT = PROJECT_ROOT / "scripts" / "build_dashboard.py"

DASHBOARD_PREFIX = "window.INVENTORY_DASHBOARD_DATA = "
DATE_RE = re.compile(r"^\d{4}/\d{2}/\d{2}$")
PRODUCT_NAME_LABEL = "產品名稱:"
MOVEMENT_REPORT_TITLE = "庫存異動明細表"


def load_dashboard_parser():
    sys.dont_write_bytecode = True
    spec = importlib.util.spec_from_file_location(
        "inventory_dashboard_average_cost_base",
        BASE_BUILD_SCRIPT,
    )
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Cannot load parser: {BASE_BUILD_SCRIPT}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


BASE = load_dashboard_parser()


def read_dashboard(path: Path) -> dict[str, Any]:
    text = path.read_text(encoding="utf-8").strip()
    if not text.startswith(DASHBOARD_PREFIX):
        raise ValueError(f"Unexpected dashboard data format: {path}")
    return json.loads(text[len(DASHBOARD_PREFIX) :].strip().rstrip(";"))


def parse_date(value: Any) -> date | None:
    text = str(value or "").strip()
    if not DATE_RE.fullmatch(text):
        return None
    return datetime.strptime(text, "%Y/%m/%d").date()


def file_sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def movement_signature(path: Path) -> date | None | bool:
    rows, _ = BASE.workbook_rows(path)
    titles = [str(cells.get("A", "")).strip() for cells in rows.values()]
    if MOVEMENT_REPORT_TITLE not in titles:
        return False
    report_dates = [
        parsed
        for cells in rows.values()
        if (parsed := parse_date(cells.get("W"))) is not None
    ]
    return max(report_dates) if report_dates else None


def latest_movement_workbook(source: Path) -> tuple[Path, date | None] | None:
    if source.is_file():
        if source.suffix.lower() != ".xlsx" or source.name.startswith("~$"):
            return None
        signature = movement_signature(source)
        return (source, signature) if signature is not False else None

    candidates: list[tuple[Path, date | None]] = []
    for path in sorted(source.glob("*.xlsx")):
        if not path.is_file() or path.name.startswith("~$"):
            continue
        try:
            signature = movement_signature(path)
        except (OSError, ValueError):
            continue
        if signature is not False:
            candidates.append((path, signature))

    if not candidates:
        return None
    return max(
        candidates,
        key=lambda candidate: (
            candidate[1] or date.min,
            candidate[0].stat().st_mtime,
        ),
    )


def parse_number(value: Any) -> float | None:
    if value in (None, ""):
        return None
    try:
        return float(str(value).replace(",", ""))
    except ValueError:
        return None


def build_average_cost(
    path: Path,
    report_date: date | None,
    dashboard: dict[str, Any],
) -> dict[str, Any]:
    rows, dimension = BASE.workbook_rows(path)
    product_rows: OrderedDict[str, dict[str, Any]] = OrderedDict()
    current_code = ""

    for row_number in sorted(rows):
        cells = rows[row_number]
        column_a = str(cells.get("A", "")).strip()

        if column_a == PRODUCT_NAME_LABEL:
            product_text = str(cells.get("B", "")).strip()
            parts = product_text.split(" ", 1)
            current_code = parts[0] if parts else ""
            if current_code:
                product_rows.setdefault(current_code, {"averageCost": None})
            continue

        if not current_code:
            continue
        average_cost = parse_number(cells.get("V"))
        if average_cost is not None:
            product_rows[current_code]["averageCost"] = average_cost

    output_items: dict[str, dict[str, float | None]] = {}
    matched = 0
    missing_cost = 0
    zero_cost = 0
    for item in dashboard.get("items", []):
        code = str(item.get("code", ""))
        movement = product_rows.get(code)
        if movement is None:
            output_items[code] = {"averageCost": None}
            missing_cost += 1
            continue

        matched += 1
        average_cost = movement["averageCost"]
        if average_cost is None:
            missing_cost += 1
        elif float(average_cost) == 0:
            zero_cost += 1
        output_items[code] = {"averageCost": average_cost}

    dashboard_item_count = len(dashboard.get("items", []))
    if matched != dashboard_item_count or missing_cost != 0:
        raise ValueError(
            "Movement workbook failed validation: "
            f"matched={matched}/{dashboard_item_count}, missingCost={missing_cost}"
        )

    return {
        "schemaVersion": 1,
        "generatedAt": datetime.now().isoformat(timespec="seconds"),
        "source": {
            "type": "averageCost",
            "filename": path.name,
            "path": str(path),
            "reportDate": report_date.isoformat() if report_date else "",
            "lastModified": datetime.fromtimestamp(path.stat().st_mtime).isoformat(
                timespec="seconds"
            ),
            "sizeBytes": path.stat().st_size,
            "sha256": file_sha256(path),
            "dimension": dimension,
        },
        "items": output_items,
        "summary": {
            "dashboardItemCount": dashboard_item_count,
            "matchedItemCount": matched,
            "missingCostCount": missing_cost,
            "zeroCostCount": zero_cost,
        },
    }


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Build protected average-cost JSON from the ERP movement report."
    )
    parser.add_argument("--source", type=Path, default=DEFAULT_SOURCE)
    parser.add_argument("--dashboard", type=Path, default=DEFAULT_DASHBOARD)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()

    selected = latest_movement_workbook(args.source)
    if selected is None:
        print("No valid movement workbook found; protected cost data is preserved.")
        raise SystemExit(3)

    workbook, report_date = selected
    dashboard = read_dashboard(args.dashboard)
    payload = build_average_cost(workbook, report_date, dashboard)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(
        json.dumps(payload, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )

    print(f"Source: {workbook}")
    print(f"Report date: {payload['source']['reportDate'] or '-'}")
    print(
        "Matched: "
        f"{payload['summary']['matchedItemCount']}/"
        f"{payload['summary']['dashboardItemCount']}"
    )
    print(f"Zero cost: {payload['summary']['zeroCostCount']}")


if __name__ == "__main__":
    main()
