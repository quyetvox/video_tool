import unittest
import json
import io
import sys
from unittest.mock import patch, MagicMock
from pathlib import Path
from storage import cmd_discover

class TestStorageDiscover(unittest.TestCase):
    def test_discover_missing_key(self):
        output = io.StringIO()
        with patch('sys.stdout', output):
            cmd_discover("non_existent_key_12345.json")
        data = json.loads(output.getvalue().strip())
        self.assertFalse(data["success"])
        self.assertIn("Không tìm thấy", data["error"])

    @patch('google.cloud.storage.Client')
    @patch('google.oauth2.service_account.Credentials.from_service_account_file')
    def test_discover_success_with_buckets_and_prefixes(self, mock_creds, mock_client_cls):
        # Create a mock temporary json key file
        test_key = Path("resources/gcs-key.json")
        if not test_key.exists():
            test_key = Path("test_key.json")
            test_key.write_text('{"type": "service_account", "project_id": "test-proj"}')
            cleanup = True
        else:
            cleanup = False

        try:
            mock_creds_inst = MagicMock()
            mock_creds_inst.project_id = "test-proj"
            mock_creds_inst.service_account_email = "test@test-proj.iam.gserviceaccount.com"
            mock_creds.return_value = mock_creds_inst

            mock_client = MagicMock()
            mock_b1 = MagicMock()
            mock_b1.name = "bucket-1"
            mock_b2 = MagicMock()
            mock_b2.name = "bucket-2"
            mock_client.list_buckets.return_value = [mock_b1, mock_b2]

            mock_bucket_obj = MagicMock()
            mock_client.bucket.return_value = mock_bucket_obj

            mock_blobs = MagicMock()
            mock_blobs.prefixes = {"prefix1/", "prefix2/"}
            mock_blobs.__iter__.return_value = []
            mock_client.list_blobs.return_value = mock_blobs

            mock_client_cls.return_value = mock_client

            output = io.StringIO()
            with patch('sys.stdout', output):
                cmd_discover(str(test_key), bucket="bucket-1")

            data = json.loads(output.getvalue().strip())
            self.assertTrue(data["success"])
            self.assertEqual(data["project_id"], "test-proj")
            self.assertEqual(data["current_bucket"], "bucket-1")
            self.assertTrue(data["can_list_buckets"])
            self.assertIn("bucket-1", data["buckets"])
            self.assertIn("prefix1", data["prefixes"])
        finally:
            if cleanup and test_key.exists():
                test_key.unlink()

if __name__ == '__main__':
    unittest.main()
