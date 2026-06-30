from __future__ import annotations

import argparse
import json
import re
import zipfile
from collections import Counter, OrderedDict, defaultdict
from datetime import datetime
from pathlib import Path
from typing import Any
from xml.etree import ElementTree as ET


DEFAULT_SOURCE = Path(r"Z:\TO承憲\ERP\IACF")
APP_SLUG = "phoenixes-film-inventory"
DEFAULT_OUTPUT = (
    Path(__file__).resolve().parents[1]
    / "public"
    / APP_SLUG
    / "dashboard-data.js"
)

NS = {"a": "http://schemas.openxmlformats.org/spreadsheetml/2006/main"}
TARGET_WAREHOUSES = ["台北倉", "台中倉", "台南倉", "高雄倉", "欣凱倉"]
DISPLAY_WAREHOUSE_NAMES = {
    "台北倉": "台北倉",
    "台中倉": "台中倉",
    "台南倉": "臺南倉",
    "高雄倉": "高雄倉",
    "欣凱倉": "欣凱倉",
}

CATEGORY_RULES = [
    {
        "category": "金山公版",
        "series": [
            {
                "name": "ES系列",
                "items": [
                    "公版ES-透明,130*290(金)",
                    "公版ES-透明,160*350",
                ],
            },
            {
                "name": "GPE系列",
                "items": [
                    "公版GPE-透明,130*350",
                    "公版GPE-透明,130*450",
                    "公版GPE-透明,160*500",
                    "公版GPE-透明,180*500",
                ],
            },
            {
                "name": "PP系列",
                "items": [
                    "公版PP-透明,130*450",
                    "公版PP-透明,160*500",
                    "公版PP-透明,180*500",
                ],
            },
        ],
    },
    {
        "category": "金山/欣凱/佑泰專板",
        "series": [
            {
                "name": "PET/ES系列",
                "items": [
                    "公版PET/ES-透明,130*350",
                    "公版PET/ES-透明,160*350",
                    "公版PET/ES電鍍,130*290",
                ],
            },
            {
                "name": "GPE系列",
                "items": [
                    "公版GPE-消光-全白,130*350",
                    "公版GPE-消光-滿版-全黑,130*350",
                    "公版GPE-透明,225*350",
                    "私版GPE-特殊透明,180*450",
                ],
            },
            {
                "name": "PP系列",
                "items": [
                    "公版PP-特殊透明,180*500",
                    "公版PP-透明,225*500",
                ],
            },
            {
                "name": "醬包膜系列",
                "items": [
                    "公版NY/PE醬包膜,180*400(60)",
                    "公版PET//CPP-MAGIC CUT,130*400",
                    "公版PET//CPP-MAGIC CUT,180*400",
                    "公版PE厚醬包膜,130*400",
                    "公版PP薄醬包膜,130*400",
                ],
            },
        ],
    },
    {
        "category": "三櫻系列",
        "series": [
            {
                "name": "膠膜",
                "items": [
                    "公版ES-透明,130*290(三)",
                    "公版ES-水果,130*290",
                    "公版ES-佳句,130*290",
                    "公版ES-繽紛,130*290",
                    "公版ES-愛護地球,130*290",
                ],
            },
            {
                "name": "紙膜",
                "items": [
                    "公版GPE紙膜-全白,130*230",
                    "公版GPE紙膜-白底花,130*230",
                    "公版GPE紙膜-城堡,130*230",
                    "公版GPE紙膜-黑金銀,130*230",
                ],
            },
        ],
    },
]


def build_category_lookup() -> dict[str, dict[str, Any]]:
    lookup: dict[str, dict[str, Any]] = {}
    for category_index, category in enumerate(CATEGORY_RULES):
        for series_index, series in enumerate(category["series"]):
            for item_index, item_name in enumerate(series["items"]):
                lookup[item_name] = {
                    "category": category["category"],
                    "series": series["name"],
                    "categorySort": category_index,
                    "seriesSort": series_index,
                    "itemSort": item_index,
                }
    return lookup


CATEGORY_LOOKUP = build_category_lookup()


def column_letters(cell_ref: str) -> str:
    return "".join(ch for ch in cell_ref if ch.isalpha())


def parse_number(value: Any) -> float | int | None:
    if value in (None, ""):
        return None
    try:
        number = float(str(value).replace(",", ""))
    except ValueError:
        return None
    return int(number) if number.is_integer() else number


def clean_number(value: float | int | None) -> float | int:
    if value is None:
        return 0
    if isinstance(value, float):
        rounded = round(value, 2)
        return int(rounded) if rounded.is_integer() else rounded
    return value


def normalize_warehouse_name(value: Any) -> str:
    return str(value or "").strip().replace("臺", "台")


def classify_product(name: str) -> dict[str, Any]:
    match = CATEGORY_LOOKUP.get(name.strip())
    if match:
        return match
    return {
        "category": "未分類",
        "series": "未分類",
        "categorySort": len(CATEGORY_RULES),
        "seriesSort": 0,
        "itemSort": 999,
    }


def derive_width_mm(name: str) -> int | None:
    match = re.search(r"(?<!\d)(130|160|180|225)\s*\*", name)
    return int(match.group(1)) if match else None


def stock_rule_for(name: str, category: str) -> dict[str, Any]:
    width = derive_width_mm(name)
    warning_below = 40
    if category != "三櫻系列" and width == 130:
        warning_below = 60

    return {
        "widthMm": width,
        "criticalAt": 20,
        "warningBelow": warning_below,
        "greenAt": warning_below,
    }


def read_cell_text(cell: ET.Element, shared_strings: list[str]) -> str:
    cell_type = cell.attrib.get("t")
    if cell_type == "s":
        value = cell.find("a:v", NS)
        if value is None or value.text is None:
            return ""
        index = int(value.text)
        return shared_strings[index] if 0 <= index < len(shared_strings) else ""

    if cell_type == "inlineStr":
        inline = cell.find("a:is", NS)
        if inline is None:
            return ""
        return "".join(
            text.text or ""
            for text in inline.iter(
                "{http://schemas.openxmlformats.org/spreadsheetml/2006/main}t"
            )
        )

    value = cell.find("a:v", NS)
    return value.text if value is not None and value.text is not None else ""


def workbook_rows(path: Path) -> tuple[dict[int, dict[str, str]], str]:
    with zipfile.ZipFile(path) as archive:
        shared_strings: list[str] = []
        if "xl/sharedStrings.xml" in archive.namelist():
            root = ET.fromstring(archive.read("xl/sharedStrings.xml"))
            for item in root.findall("a:si", NS):
                shared_strings.append(
                    "".join(
                        text.text or ""
                        for text in item.iter(
                            "{http://schemas.openxmlformats.org/spreadsheetml/2006/main}t"
                        )
                    )
                )

        sheet_names = [
            name
            for name in archive.namelist()
            if name.startswith("xl/worksheets/sheet") and name.endswith(".xml")
        ]
        if not sheet_names:
            raise ValueError(f"No worksheet found in {path}")

        sheet = ET.fromstring(archive.read(sheet_names[0]))
        dimension = sheet.find("a:dimension", NS)
        dimension_ref = dimension.attrib.get("ref", "") if dimension is not None else ""

        rows: dict[int, dict[str, str]] = {}
        for row in sheet.findall(".//a:sheetData/a:row", NS):
            row_number = int(row.attrib["r"])
            cells: dict[str, str] = {}
            for cell in row.findall("a:c", NS):
                text = read_cell_text(cell, shared_strings)
                if text != "":
                    cells[column_letters(cell.attrib.get("r", ""))] = text.strip()
            if cells:
                rows[row_number] = cells

        return rows, dimension_ref


def latest_xlsx(source: Path) -> Path:
    if source.is_file() and source.suffix.lower() == ".xlsx":
        return source

    files = [
        item
        for item in source.glob("*.xlsx")
        if item.is_file() and not item.name.startswith("~$")
    ]
    if not files:
        raise FileNotFoundError(f"No .xlsx files found in {source}")
    return max(files, key=lambda item: item.stat().st_mtime)


def parse_inventory(path: Path) -> dict[str, Any]:
    rows, dimension = workbook_rows(path)
    products: OrderedDict[str, dict[str, Any]] = OrderedDict()
    current_code: str | None = None
    report_dates: set[str] = set()
    page_labels: set[str] = set()
    warehouse_rows: Counter[str] = Counter()

    for cells in rows.values():
        q_value = str(cells.get("Q", ""))
        if re.match(r"^\d{4}/\d{2}/\d{2}$", q_value):
            report_dates.add(q_value)
        if re.match(r"^\d+\s*/\s*\d+$", q_value):
            page_labels.add(q_value)

    for row_number in sorted(rows):
        cells = rows[row_number]
        col_a = str(cells.get("A", ""))
        code = str(cells.get("B", "")).strip()

        if col_a.endswith(":") and code.startswith("F"):
            name = str(cells.get("F", "")).strip()
            spec = " ".join(
                str(cells.get(col, "")).strip()
                for col in ["K", "L", "M", "N", "O", "P"]
                if cells.get(col, "")
            )
            if code not in products:
                products[code] = {
                    "code": code,
                    "name": name,
                    "spec": spec,
                    "warehouses": {name: 0 for name in TARGET_WAREHOUSES},
                    "otherWarehouses": defaultdict(float),
                    "subtotal": None,
                }
            elif spec and not products[code]["spec"]:
                products[code]["spec"] = spec

            current_code = code
            continue

        if current_code is None:
            continue

        q_number = parse_number(cells.get("Q"))
        if col_a == "小計:":
            products[current_code]["subtotal"] = clean_number(q_number)
            continue

        if q_number is None:
            continue

        warehouse = normalize_warehouse_name(cells.get("F") or cells.get("A"))
        if not warehouse or warehouse.endswith(":"):
            continue

        warehouse_rows[warehouse] += 1
        if warehouse in TARGET_WAREHOUSES:
            products[current_code]["warehouses"][warehouse] += q_number
        else:
            products[current_code]["otherWarehouses"][warehouse] += q_number

    items: list[dict[str, Any]] = []
    other_totals: Counter[str] = Counter()

    for product in products.values():
        warehouses = {
            key: clean_number(value)
            for key, value in product["warehouses"].items()
        }
        visible_total = clean_number(sum(product["warehouses"].values()))
        classification = classify_product(product["name"])
        stock_rule = stock_rule_for(product["name"], classification["category"])
        other_warehouses = {
            key: clean_number(value)
            for key, value in product["otherWarehouses"].items()
            if value
        }
        for key, value in other_warehouses.items():
            other_totals[key] += float(value)

        items.append(
            {
                "code": product["code"],
                "name": product["name"],
                "spec": product["spec"],
                "category": classification["category"],
                "series": classification["series"],
                "widthMm": stock_rule["widthMm"],
                "stockRule": stock_rule,
                "sort": {
                    "category": classification["categorySort"],
                    "series": classification["seriesSort"],
                    "item": classification["itemSort"],
                },
                "warehouses": warehouses,
                "visibleTotal": visible_total,
                "subtotal": product["subtotal"],
                "otherWarehouses": other_warehouses,
                "otherTotal": clean_number(sum(product["otherWarehouses"].values())),
            }
        )

    items.sort(
        key=lambda item: (
            item["sort"]["category"],
            item["sort"]["series"],
            item["sort"]["item"],
            item["name"],
            item["code"],
        )
    )

    warehouse_totals = {
        warehouse: clean_number(
            sum(float(item["warehouses"][warehouse]) for item in items)
        )
        for warehouse in TARGET_WAREHOUSES
    }

    visible_nonzero = [item for item in items if item["visibleTotal"] != 0]
    hidden_stock_items = [item for item in items if item["otherTotal"] != 0]
    unmatched_items = [item for item in items if item["category"] == "未分類"]
    category_counts = Counter(item["category"] for item in items)
    series_counts = Counter((item["category"], item["series"]) for item in items)

    return {
        "generatedAt": datetime.now().isoformat(timespec="seconds"),
        "source": {
            "path": str(path),
            "filename": path.name,
            "lastModified": datetime.fromtimestamp(path.stat().st_mtime).isoformat(
                timespec="seconds"
            ),
            "sizeBytes": path.stat().st_size,
            "dimension": dimension,
            "reportDates": sorted(report_dates),
            "pages": sorted(page_labels),
        },
        "warehouseOrder": TARGET_WAREHOUSES,
        "warehouseLabels": DISPLAY_WAREHOUSE_NAMES,
        "categoryRules": CATEGORY_RULES,
        "items": items,
        "summary": {
            "itemCount": len(items),
            "visibleNonzeroCount": len(visible_nonzero),
            "visibleZeroCount": len(items) - len(visible_nonzero),
            "categoryCounts": dict(category_counts),
            "seriesCounts": {
                f"{category}::{series}": count
                for (category, series), count in sorted(series_counts.items())
            },
            "unmatchedItems": [
                {"code": item["code"], "name": item["name"]}
                for item in unmatched_items
            ],
            "warehouseTotals": warehouse_totals,
            "visibleGrandTotal": clean_number(sum(warehouse_totals.values())),
            "hiddenWarehouseTotals": {
                key: clean_number(value)
                for key, value in sorted(other_totals.items())
                if value
            },
            "hiddenStockItemCount": len(hidden_stock_items),
            "warehouseRowsFound": dict(sorted(warehouse_rows.items())),
        },
    }


def write_dashboard_data(data: dict[str, Any], output: Path) -> None:
    output.parent.mkdir(parents=True, exist_ok=True)
    payload = json.dumps(data, ensure_ascii=False, indent=2)
    output.write_text(
        "window.INVENTORY_DASHBOARD_DATA = " + payload + ";\n",
        encoding="utf-8",
    )


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Build the film inventory dashboard data file."
    )
    parser.add_argument("--source", type=Path, default=DEFAULT_SOURCE)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    args = parser.parse_args()

    workbook = latest_xlsx(args.source)
    data = parse_inventory(workbook)
    write_dashboard_data(data, args.output)

    print(f"Source: {workbook}")
    print(f"Output: {args.output}")
    print(f"Items: {data['summary']['itemCount']}")
    print(f"Visible nonzero: {data['summary']['visibleNonzeroCount']}")
    print(f"Visible grand total: {data['summary']['visibleGrandTotal']}")


if __name__ == "__main__":
    main()
