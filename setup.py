#!/usr/bin/env python3

from pathlib import Path

from setuptools import find_packages, setup

packages = find_packages(exclude=("tests*",))
package_data = {pkg: ("py.typed",) for pkg in packages}
install_requires = Path("requirements.txt").read_text().splitlines()

setup(
    name="Coq",
    python_requires=">=3.8.2",
    version="0.1.10",
    description="Nvim completion source",
    long_description=Path("README.md").read_text(),
    long_description_content_type="text/markdown",
    author="ms-jpq",
    author_email="github@bigly.dog",
    url="https://github.com/ms-jpq/coq_nvim",
    packages=packages,
    package_data=package_data,
    install_requires=install_requires,
)
