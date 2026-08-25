#!/usr/bin/env python3
import argparse
import sys
from pathlib import Path

# Add lib directory to sys.path
sys.path.insert(0, str(Path(__file__).parent / "lib"))

from rich.console import Console
from rich.table import Table
from rich.panel import Panel
from utils.storage_manager import StorageManager

console = Console()


def format_size(size_bytes: int) -> str:
    """Format bytes into human readable string."""
    if size_bytes == 0:
        return "0 B"
    for unit in ['B', 'KB', 'MB', 'GB']:
        if abs(size_bytes) < 1024.0:
            return f"{size_bytes:.2f} {unit}"
        size_bytes /= 1024.0
    return f"{size_bytes:.2f} TB"


def cmd_status(mgr: StorageManager, project_name: str):
    console.print(f"[bold cyan]🔍 Kiểm tra trạng thái Cloud Storage dự án:[/bold cyan] [bold yellow]{project_name}[/bold yellow]")
    
    if not mgr.is_connected():
        key_status = f"[green]Tìm thấy ({mgr.key_file})[/green]" if (mgr.key_file and mgr.key_file.exists()) else f"[red]Chưa có file key tại {mgr.key_file}[/red]"
        console.print(Panel(
            f"[bold red]❌ CHƯA KẾT NỐI ĐƯỢC GOOGLE CLOUD STORAGE[/bold red]\n\n"
            f"• Bucket: [yellow]{mgr.bucket_name}[/yellow]\n"
            f"• Prefix: [yellow]{mgr.base_prefix}/{project_name}[/yellow]\n"
            f"• Key File: {key_status}\n\n"
            f"[bold white]👉 Hướng dẫn khắc phục:[/bold white]\n"
            f"1. Tải Service Account Key JSON từ Google Cloud Console.\n"
            f"2. Đổi tên thành [bold green]gcs-key.json[/bold green] và đặt vào thư mục gốc dự án [bold green]{mgr.assets_dir.parent}[/bold green].",
            title="GCS Connection Status",
            border_style="red"
        ))
        return

    status = mgr.get_status()
    counts = status["counts"]
    bytes_info = status["bytes"]

    console.print(f"☁️ [bold]Cloud Target:[/bold] [green]gs://{status['bucket']}/{status['prefix']}[/green] [dim](🟢 Native GCS Key)[/dim]")
    console.print(f"📊 [bold]Tổng quan:[/bold] Local: [cyan]{format_size(bytes_info['local'])}[/cyan] | Cloud: [magenta]{format_size(bytes_info['cloud'])}[/magenta]")
    console.print(f"📌 [bold]Thống kê:[/bold] Đồng bộ: [green]{counts['synced']}[/green] | Chỉ Local: [yellow]{counts['localOnly']}[/yellow] | Chỉ Cloud: [blue]{counts['cloudOnly']}[/blue] | Khác biệt: [red]{counts['modified']}[/red]\n")

    table = Table(title=f"Danh Sách Tệp Dự Án [{project_name}]", border_style="dim")
    table.add_column("File / Đường dẫn", style="cyan")
    table.add_column("Trạng Thái", justify="center")
    table.add_column("Kích Thước", justify="right")
    table.add_column("Vị Trí Lưu Trữ", justify="center")

    for f in status["files"]:
        st = f["status"]
        if st == "synced":
            status_str = "[bold green]🔄 Đã đồng bộ[/bold green]"
            loc_str = "💻 Local + ☁️ Cloud"
        elif st == "local_only":
            status_str = "[bold yellow]💻 Chỉ Local[/bold yellow]"
            loc_str = "💻 Local SSD"
        elif st == "cloud_only":
            status_str = "[bold blue]☁️ Chỉ Cloud[/bold blue]"
            loc_str = "☁️ GCS Cloud"
        elif st == "modified":
            status_str = "[bold red]⚠️ Lệch Size[/bold red]"
            loc_str = "💻 / ☁️ Không khớp"
        else:
            status_str = st
            loc_str = "-"

        table.add_row(
            f["relPath"],
            status_str,
            format_size(f["sizeBytes"]),
            loc_str
        )

    console.print(table)


def cmd_sync_down(mgr: StorageManager, project_name: str, files: list):
    console.print(f"[bold cyan]⬇️ Đang kéo tệp từ Cloud về Local máy Mac:[/bold cyan] [bold yellow]{project_name}[/bold yellow]")
    try:
        res = mgr.sync_down(files=files)
        console.print(f"✅ Đã tải: [bold green]{res['transferredCount']}[/bold green] tệp ({format_size(res['totalBytes'])})")
        if res['skippedCount'] > 0:
            console.print(f"⏭️ Bỏ qua: [dim]{res['skippedCount']} tệp (đã có sẵn)[/dim]")
        if res['failedCount'] > 0:
            console.print(f"[bold red]❌ Thất bại: {res['failedCount']} tệp[/bold red]")
            for fail in res['failed']:
                console.print(f"   - {fail['file']}: {fail['error']}")
            if res['transferredCount'] == 0 and res['skippedCount'] == 0:
                sys.exit(1)
    except Exception as e:
        console.print(f"[bold red]❌ Lỗi sync-down:[/bold red] {e}")
        sys.exit(1)


def cmd_sync_up(mgr: StorageManager, project_name: str, files: list):
    console.print(f"[bold cyan]⬆️ Đang đẩy tệp từ Local lên Cloud Storage:[/bold cyan] [bold yellow]{project_name}[/bold yellow]")
    try:
        res = mgr.sync_up(files=files)
        console.print(f"✅ Đã đẩy lên: [bold green]{res['transferredCount']}[/bold green] tệp ({format_size(res['totalBytes'])})")
        if res['skippedCount'] > 0:
            console.print(f"⏭️ Bỏ qua: [dim]{res['skippedCount']} tệp (trên cloud đã cập nhật)[/dim]")
        if res['failedCount'] > 0:
            console.print(f"[bold red]❌ Thất bại: {res['failedCount']} tệp[/bold red]")
            for fail in res['failed']:
                console.print(f"   - {fail['file']}: {fail['error']}")
            if res['transferredCount'] == 0 and res['skippedCount'] == 0:
                sys.exit(1)
    except Exception as e:
        console.print(f"[bold red]❌ Lỗi sync-up:[/bold red] {e}")
        sys.exit(1)


def cmd_offload(mgr: StorageManager, project_name: str, files: list):
    console.print(f"[bold cyan]🧹 Đang giải phóng ổ cứng SSD (Offload):[/bold cyan] [bold yellow]{project_name}[/bold yellow]")
    try:
        res = mgr.offload_local(files=files)
        console.print(f"🎉 Đã giải phóng: [bold green]{res['freedCount']}[/bold green] tệp. [bold green]Tiết kiệm được {format_size(res['totalFreedBytes'])} SSD[/bold green]!")
        for freed in res['freed']:
            console.print(f"   - 🗑️ [dim]Đã xoá local:[/dim] {freed['file']} (+{format_size(freed['freedBytes'])})")

        if res['rejectedCount'] > 0:
            console.print(f"\n[bold yellow]⚠️ {res['rejectedCount']} tệp KHÔNG được xoá do chưa an toàn trên Cloud:[/bold yellow]")
            for rej in res['rejected']:
                console.print(f"   - 🔒 {rej['file']}: {rej['reason']}")

        if res['failedCount'] > 0:
            console.print(f"\n[bold red]❌ Thất bại: {res['failedCount']} tệp[/bold red]")
            for fail in res['failed']:
                console.print(f"   - {fail['file']}: {fail['error']}")
            if res['freedCount'] == 0:
                sys.exit(1)
    except Exception as e:
        console.print(f"[bold red]❌ Lỗi offload:[/bold red] {e}")
        sys.exit(1)


def cmd_delete_cloud(mgr: StorageManager, project_name: str, files: list):
    console.print(f"[bold red]🗑️ Đang xoá tệp trên Cloud Storage:[/bold red] [bold yellow]{project_name}[/bold yellow]")
    try:
        res = mgr.delete_cloud(files=files)
        console.print(f"✅ Đã xoá: [bold green]{res['deletedCount']}[/bold green] tệp khỏi Cloud")
        if res['failedCount'] > 0:
            console.print(f"[bold red]❌ Thất bại: {res['failedCount']} tệp[/bold red]")
            for fail in res['failed']:
                console.print(f"   - {fail['file']}: {fail['error']}")
    except Exception as e:
        console.print(f"[bold red]❌ Lỗi delete-cloud:[/bold red] {e}")
        sys.exit(1)


def cmd_refresh(mgr: StorageManager, project_name: str):
    console.print(f"[bold cyan]🔄 Đang làm mới dữ liệu Cloud (Direct API Refresh):[/bold cyan] [bold yellow]{project_name or 'toàn bộ'}[/bold yellow]")
    res = mgr.refresh_mount(target_dir=project_name if project_name != "all" else "")
    if res.get("success"):
        console.print(f"✅ [bold green]Làm mới thành công![/bold green] {res.get('message')}")
    else:
        console.print(f"❌ [bold red]Lỗi làm mới:[/bold red] {res.get('error')}")


def cmd_browse(mgr: StorageManager, path: str):
    data = mgr.browse(path)
    import json
    print(json.dumps(data, ensure_ascii=False))


def cmd_status_json(mgr: StorageManager):
    status = mgr.get_status()
    import json
    print(json.dumps(status, ensure_ascii=False))


def cmd_test_connection(key_file: str = None, bucket: str = None, prefix: str = None):
    import json
    mgr = StorageManager()
    if key_file:
        mgr.key_file = Path(key_file)
    if bucket:
        mgr.bucket_name = bucket
    if prefix:
        mgr.base_prefix = prefix.strip("/")

    connected = mgr.is_connected()
    res = {
        "connected": connected,
        "bucket": mgr.bucket_name,
        "prefix": mgr.base_prefix,
        "key_file": str(mgr.key_file) if mgr.key_file else "",
        "key_exists": bool(mgr.key_file and mgr.key_file.exists()),
    }
    print(json.dumps(res, ensure_ascii=False))


def main():
    parser = argparse.ArgumentParser(
        description="Sub-Video Cloud Native Storage CLI - Quản lý tệp Cloud Storage qua Direct API"
    )
    subparsers = parser.add_subparsers(dest="action", help="Lệnh thực hiện")

    # browse (JSON output)
    p_browse = subparsers.add_parser("browse", help="Duyệt cây thư mục Cloud dạng phân cấp JSON")
    p_browse.add_argument("path", type=str, nargs="?", default="", help="Đường dẫn duyệt (để trống = root)")

    # status-json
    p_status_json = subparsers.add_parser("status-json", help="Lấy trạng thái chi tiết dự án dạng JSON")
    p_status_json.add_argument("project", type=str, nargs="?", default="default", help="Tên project")

    # test-connection
    p_test = subparsers.add_parser("test-connection", help="Kiểm tra kết nối Google Cloud Storage")
    p_test.add_argument("--key", type=str, default=None, help="Đường dẫn key file JSON")
    p_test.add_argument("--bucket", type=str, default=None, help="Tên GCS Bucket")
    p_test.add_argument("--prefix", type=str, default=None, help="Base prefix")

    # status
    p_status = subparsers.add_parser("status", help="Kiểm tra trạng thái đồng bộ Local vs Cloud")
    p_status.add_argument("project", type=str, nargs="?", default="default", help="Tên project (ví dụ: foods, edamame)")

    # sync-down
    p_down = subparsers.add_parser("sync-down", help="Kéo video/dữ liệu từ Cloud về Local máy Mac")
    p_down.add_argument("project", type=str, nargs="?", default="default", help="Tên project")
    p_down.add_argument("--files", nargs="*", default=None, help="Danh sách tên file cụ thể cần tải về")

    # sync-up
    p_up = subparsers.add_parser("sync-up", help="Đẩy video/kết quả từ Local lên Cloud Storage")
    p_up.add_argument("project", type=str, nargs="?", default="default", help="Tên project")
    p_up.add_argument("--files", nargs="*", default=None, help="Danh sách tên file cụ thể cần tải lên")

    # offload
    p_offload = subparsers.add_parser("offload", help="Giải phóng dung lượng SSD Mac (chỉ xoá local khi đã an toàn trên Cloud)")
    p_offload.add_argument("project", type=str, nargs="?", default="default", help="Tên project")
    p_offload.add_argument("--files", nargs="*", default=None, help="Danh sách tên file cụ thể cần giải phóng")

    # delete-cloud
    p_del = subparsers.add_parser("delete-cloud", help="Xoá vĩnh viễn tệp trên Cloud Storage")
    p_del.add_argument("project", type=str, nargs="?", default="default", help="Tên project")
    p_del.add_argument("--files", nargs="+", required=True, help="Danh sách tên file cần xoá trên Cloud")

    # refresh
    p_refresh = subparsers.add_parser("refresh", help="Làm mới bộ nhớ đệm Cloud")
    p_refresh.add_argument("project", type=str, nargs="?", default="all", help="Tên project (hoặc 'all' để làm mới toàn bộ)")

    # info
    p_info = subparsers.add_parser("info", help="Xem thông tin cấu hình Cloud Storage")

    args = parser.parse_args()

    if not args.action:
        parser.print_help()
        sys.exit(0)

    if args.action == "test-connection":
        cmd_test_connection(args.key, args.bucket, args.prefix)
        return

    mgr = StorageManager(
        project_name=getattr(args, "project", "default")
    )

    if args.action == "browse":
        cmd_browse(mgr, args.path)
    elif args.action == "status-json":
        cmd_status_json(mgr)
    elif args.action == "status":
        cmd_status(mgr, args.project)
    elif args.action == "sync-down":
        cmd_sync_down(mgr, args.project, args.files)
    elif args.action == "sync-up":
        cmd_sync_up(mgr, args.project, args.files)
    elif args.action == "offload":
        cmd_offload(mgr, args.project, args.files)
    elif args.action == "refresh":
        cmd_refresh(mgr, args.project)
    elif args.action == "delete-cloud":
        cmd_delete_cloud(mgr, args.project, args.files)
    elif args.action == "info":
        key_status = f"[green]Đã có ({mgr.key_file})[/green]" if (mgr.key_file and mgr.key_file.exists()) else f"[red]Chưa có file {mgr.key_file}[/red]"
        console.print(Panel(
            f"☁️ [bold]GCS Bucket:[/bold] [cyan]gs://{mgr.bucket_name}/{mgr.base_prefix}[/cyan]\n"
            f"🔑 [bold]Service Account Key:[/bold] {key_status}\n"
            f"🟢 [bold]GCS Native Status:[/bold] {'[green]Đã kết nối thành công (OK)[/green]' if mgr.is_connected() else '[red]Chưa kết nối (Cần file gcs-key.json)[/red]'}\n"
            f"💻 [bold]Local Assets:[/bold] {mgr.assets_dir}\n",
            title="Native Google Cloud Storage Info",
            border_style="cyan"
        ))


if __name__ == "__main__":
    main()
