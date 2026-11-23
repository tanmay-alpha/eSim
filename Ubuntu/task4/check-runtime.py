"""Run with the eSim environment's bin/python; no display or simulator needed."""
import sys
from pathlib import Path

import matplotlib
import psutil
from PyQt5 import QtCore, QtGui, QtWidgets

if sys.prefix == sys.base_prefix:
    sys.exit("Use the eSim virtual environment, not system Python")
# Exercise the native extensions and the noninteractive plotting backend.
from matplotlib.backends.backend_agg import FigureCanvasAgg
from matplotlib.figure import Figure

figure = Figure(figsize=(1, 1))
figure.subplots().plot([0, 1])
FigureCanvasAgg(figure).draw()
assert psutil.Process().pid > 0
assert QtGui.QColor('red').red() == 255 and QtWidgets.QMainWindow is not None
print(f'Python {sys.version.split()[0]}; Qt {QtCore.qVersion()}; matplotlib {matplotlib.__version__}; psutil {psutil.__version__}')
for module in (QtCore, matplotlib, psutil):
    print(Path(module.__file__).resolve())
