FROM python:3.11-slim

ENV PYTHONUNBUFFERED=1

WORKDIR /code

# Instala primero las dependencias 
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copia todo el proyecto al contenedor
COPY . .

EXPOSE 5000

# Ejecuta el archivo app/app.py
CMD ["python", "app/app.py"]


