FROM python:3.11-alpine
WORKDIR /app
RUN pip install --upgrade pip
RUN pip install --no-cache-dir 'pyserial>=3.5' 
COPY serial2http.py /app
COPY SERIAL2HTTP.rsc /app/scripts/SERIAL2HTTP.rsc
CMD [ "python", "/app/serial2http.py" ]
