FROM python:3.12-slim
WORKDIR /app
COPY inventory.py client.py ./
EXPOSE 8080
CMD ["python", "-u", "inventory.py"]
