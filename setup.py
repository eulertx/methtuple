import os

from setuptools import setup, find_packages

here = os.path.abspath(os.path.dirname(__file__))

README = open(os.path.join(here, 'README.md')).read()
CHANGES = '' # open(os.path.join(here, 'CHANGES.md')).read()

setup(
  name='comethylation',
  version='1.0.1',
  description='comethylation',
  long_description=README + '\n\n' +  CHANGES,
  classifiers=[
    "Programming Language :: Python",
      "License :: OSI Approved :: GNU General Public License v2 (GPLv2)",
    ],
  author='Peter Hickey',
  author_email='peter.hickey@gmail.com',
  url='https://github.com/PeteHaitch/comethylation',
  keywords='bisulfite sequencing methylation bismark bioinformatics',
  packages=find_packages(),
  include_package_data=True,
  zip_safe=False,
  install_requires=['pysam'],
  test_suite="comethylation.tests",
  scripts = [
    'comethylation/scripts/comethylation'
  ]
)