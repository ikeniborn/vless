#!/usr/bin/env python3
"""
VLESS Architecture Documentation Validator

Validates all YAML architecture documentation files against their JSON schemas.
Ensures 100% structural correctness and compliance with specifications.

Usage:
    python3 validate_architecture_docs.py [--verbose]
"""

import json
import sys
import os
from pathlib import Path
from typing import Dict, List, Tuple, Any

try:
    import yaml
    from jsonschema import validate, ValidationError, SchemaError
except ImportError:
    print("ERROR: Required libraries not found.")
    print("Install with: pip3 install pyyaml jsonschema")
    sys.exit(1)


class ArchitectureValidator:
    """Validates YAML documentation against JSON schemas."""

    def __init__(self, base_path: str, verbose: bool = False):
        self.base_path = Path(base_path)
        self.verbose = verbose
        self.yaml_dir = self.base_path / "yaml"
        self.schema_dir = self.base_path / "schemas"

        # Define YAML-to-Schema mappings
        self.validations = [
            ("docker.yaml", "docker-schema.json", "Docker Architecture"),
            ("config.yaml", "config-schema.json", "Configuration Architecture"),
            ("cli.yaml", "cli-schema.json", "CLI Interface"),
            ("lib-modules.yaml", "lib-modules-schema.json", "Library Modules"),
            ("data-flows.yaml", "data-flows-schema.json", "Data Flows"),
            ("dependencies.yaml", "dependencies-schema.json", "Dependencies"),
        ]

        self.results: List[Tuple[str, bool, str]] = []

    def load_yaml(self, yaml_file: Path) -> Dict[str, Any]:
        """Load and parse YAML file."""
        try:
            with open(yaml_file, 'r', encoding='utf-8') as f:
                return yaml.safe_load(f)
        except yaml.YAMLError as e:
            raise ValueError(f"YAML parsing error: {e}")
        except FileNotFoundError:
            raise FileNotFoundError(f"YAML file not found: {yaml_file}")

    def load_schema(self, schema_file: Path) -> Dict[str, Any]:
        """Load and parse JSON schema."""
        try:
            with open(schema_file, 'r', encoding='utf-8') as f:
                return json.load(f)
        except json.JSONDecodeError as e:
            raise ValueError(f"JSON schema parsing error: {e}")
        except FileNotFoundError:
            raise FileNotFoundError(f"Schema file not found: {schema_file}")

    def validate_file(self, yaml_name: str, schema_name: str, description: str) -> Tuple[bool, str]:
        """Validate a single YAML file against its schema."""
        yaml_path = self.yaml_dir / yaml_name
        schema_path = self.schema_dir / schema_name

        if self.verbose:
            print(f"\n{'='*70}")
            print(f"Validating: {description}")
            print(f"YAML: {yaml_path}")
            print(f"Schema: {schema_path}")
            print(f"{'='*70}")

        try:
            # Load files
            yaml_data = self.load_yaml(yaml_path)
            schema_data = self.load_schema(schema_path)

            # Validate
            validate(instance=yaml_data, schema=schema_data)

            message = f"✅ PASSED: {description}"
            if self.verbose:
                print(f"\n{message}")
                print(f"   File: {yaml_name}")
                print(f"   Schema: {schema_name}")

            return (True, message)

        except FileNotFoundError as e:
            message = f"❌ FAILED: {description}\n   Error: {e}"
            return (False, message)

        except ValidationError as e:
            # Format validation error with details
            error_path = " → ".join(str(p) for p in e.path) if e.path else "root"
            message = (
                f"❌ FAILED: {description}\n"
                f"   Error Path: {error_path}\n"
                f"   Error: {e.message}\n"
                f"   Validator: {e.validator} = {e.validator_value}"
            )

            if self.verbose:
                print(f"\n{message}")
                if e.instance:
                    print(f"   Invalid Value: {e.instance}")

            return (False, message)

        except SchemaError as e:
            message = (
                f"❌ FAILED: {description}\n"
                f"   Schema Error: {e.message}\n"
                f"   Invalid Schema: {schema_name}"
            )
            return (False, message)

        except Exception as e:
            message = (
                f"❌ FAILED: {description}\n"
                f"   Unexpected Error: {type(e).__name__}: {e}"
            )
            return (False, message)

    def validate_all(self) -> bool:
        """Validate all YAML files. Returns True if all pass."""
        print("="*70)
        print("VLESS Architecture Documentation Validator")
        print("="*70)
        print(f"Base Path: {self.base_path}")
        print(f"YAML Directory: {self.yaml_dir}")
        print(f"Schema Directory: {self.schema_dir}")
        print(f"Total Validations: {len(self.validations)}")
        print("="*70)

        all_passed = True

        for yaml_name, schema_name, description in self.validations:
            success, message = self.validate_file(yaml_name, schema_name, description)
            self.results.append((description, success, message))

            if not success:
                all_passed = False

            if not self.verbose:
                print(message)

        return all_passed

    def print_summary(self):
        """Print validation summary."""
        print("\n" + "="*70)
        print("VALIDATION SUMMARY")
        print("="*70)

        passed = sum(1 for _, success, _ in self.results if success)
        failed = len(self.results) - passed

        print(f"Total Files: {len(self.results)}")
        print(f"✅ Passed: {passed}")
        print(f"❌ Failed: {failed}")
        print("="*70)

        if failed > 0:
            print("\nFailed Validations:")
            for description, success, message in self.results:
                if not success:
                    print(f"\n{message}")

        print("\n" + "="*70)
        if failed == 0:
            print("🎉 ALL VALIDATIONS PASSED - 100% ACCURACY ACHIEVED")
            print("Architecture documentation is structurally correct!")
        else:
            print("⚠️  VALIDATION FAILED - CORRECTIONS REQUIRED")
            print(f"Please fix {failed} file(s) before proceeding.")
        print("="*70 + "\n")

    def get_file_stats(self):
        """Print statistics about YAML files."""
        print("\n" + "="*70)
        print("DOCUMENTATION STATISTICS")
        print("="*70)

        total_lines = 0
        total_size = 0

        for yaml_name, _, description in self.validations:
            yaml_path = self.yaml_dir / yaml_name
            if yaml_path.exists():
                size = yaml_path.stat().st_size
                with open(yaml_path, 'r') as f:
                    lines = len(f.readlines())

                total_lines += lines
                total_size += size

                print(f"{description:30} | {lines:5} lines | {size/1024:.1f} KB")

        print("="*70)
        print(f"{'TOTAL':30} | {total_lines:5} lines | {total_size/1024:.1f} KB")
        print("="*70)


def main():
    """Main entry point."""
    import argparse

    parser = argparse.ArgumentParser(
        description="Validate VLESS architecture documentation against JSON schemas"
    )
    parser.add_argument(
        "--verbose", "-v",
        action="store_true",
        help="Enable verbose output with detailed error messages"
    )
    parser.add_argument(
        "--base-path",
        default="/home/ikeniborn/Documents/Project/vless/docs/architecture",
        help="Base path to architecture documentation (default: /home/ikeniborn/Documents/Project/vless/docs/architecture)"
    )
    parser.add_argument(
        "--stats",
        action="store_true",
        help="Show documentation statistics"
    )

    args = parser.parse_args()

    # Validate base path exists
    if not Path(args.base_path).exists():
        print(f"ERROR: Base path does not exist: {args.base_path}")
        sys.exit(1)

    # Create validator and run
    validator = ArchitectureValidator(args.base_path, verbose=args.verbose)

    # Show stats if requested
    if args.stats:
        validator.get_file_stats()

    # Run validation
    all_passed = validator.validate_all()

    # Print summary
    validator.print_summary()

    # Exit with appropriate code
    sys.exit(0 if all_passed else 1)


if __name__ == "__main__":
    main()
