#!/usr/bin/env python3
"""Record a selected imagegen source after its decoded output has been copied."""

from __future__ import annotations

import argparse
import json
from datetime import datetime, timezone
from pathlib import Path


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--run-dir", type=Path, required=True)
    parser.add_argument("--job-id", required=True)
    parser.add_argument("--source", type=Path)
    parser.add_argument("--status", choices=("pending", "complete"), default="complete")
    args = parser.parse_args()

    manifest_path = args.run_dir / "imagegen-jobs.json"
    data = json.loads(manifest_path.read_text(encoding="utf-8"))
    for job in data["jobs"]:
        if job["id"] == args.job_id:
            if args.status == "complete":
                if args.source is None:
                    raise SystemExit("--source is required when marking complete")
                output = args.run_dir / Path(job["output_path"].replace("\\", "/"))
                if not output.exists():
                    raise SystemExit(f"Decoded output does not exist: {output}")
                job.update(
                    {
                        "status": "complete",
                        "source_path": str(args.source.resolve()),
                        "completed_at": datetime.now(timezone.utc).isoformat(),
                    }
                )
            else:
                job["status"] = "pending"
                job.pop("completed_at", None)
            break
    else:
        raise SystemExit(f"Unknown job: {args.job_id}")
    manifest_path.write_text(
        json.dumps(data, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    print(f"Marked {args.job_id} {args.status}")


if __name__ == "__main__":
    main()
