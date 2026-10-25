# Aplicación móvil con bibliotecas de Machine Learning para pronosticar variaciones de voltaje eléctrico en una industria química peruana

## Product Backlog

### Cell Management Bounded Context

| ID    | Como                | Quiero                                                    | Para                                                                        |
| ----- | ------------------- | --------------------------------------------------------- | --------------------------------------------------------------------------- |
| US009 | Ingeniero de Planta | registrar las celdas eléctricas de la empresa             | tener la información de las celdas en el sistema                            |
| US010 | Ingeniero de Planta | editar los datos de una celda eléctrica                   | mantener la información de las celdas eléctricas actualizada                |
| US011 | Ingeniero de Planta | eliminar celdas eléctricas registradas                    | mantener en el sistema solamente las celdas con las que cuenta la empresa   |
| US012 | Ingeniero de Planta | registrar los cátodos y ánodos de cada celda              | mantener la información de los componentes de cada celda en el sistema      |
| US013 | Ingeniero de Planta | eliminar cátodos o ánodos registrados                     | mantener únicamente los componentes que estén en uso                        |
| US014 | Ingeniero de Planta | intercambiar los cátodos y ánodos asignados en cada celda | regular la carga de voltaje                                                 |
| US015 | Ingeniero de Planta | editar los datos de un cátodo o ánodo                     | mantener su información actualizada a lo largo del tiempo                   |
| US016 | Ingeniero de Planta | generar un código de barras sobre cada celda              | identificar de manera rápida qué cátodo y ánodo está asignado a dicha celda |
| US017 | Ingeniero de Planta | poder descargar el código de barras de cada celda         | imprimir el código de barras                                                |

#### Criterios de aceptación

##### US009 · Registrar las celdas eléctricas de la empresa

- **E01: Registro exitoso de una celda eléctrica**
  - **Dado que** el Ingeniero de Planta ingresa los datos requeridos de una nueva celda eléctrica
  - **Cuando** el ingeniero confirma el registro
  - **Entonces** el sistema almacena la celda eléctrica
  - **Y** muestra un mensaje de confirmación del registro exitoso.
- **E02: Registro con datos incompletos**
  - **Dado que** el Ingeniero de Planta no ha completado todos los campos obligatorios de la celda
  - **Cuando** el ingeniero intenta registrar la celda
  - **Entonces** el sistema rechaza el registro
  - **Y** muestra un mensaje indicando los campos obligatorios faltantes.

##### US010 · Editar los datos de una celda eléctrica

- **E01: Edición exitosa de una celda eléctrica**
  - **Dado que** el Ingeniero de Planta registra una celda eléctrica en el sistema
  - **Cuando** el Ingeniero de Planta desea modificar sus datos y confirma los cambios
  - **Entonces** el sistema actualiza la información de la celda eléctrica.
- **E02: Edición con datos inválidos**
  - **Dado que** el Ingeniero de Planta ingresa un valor no válido en algún campo de la celda
  - **Cuando** intenta editar y guardar los cambios
  - **Entonces** el sistema rechaza la edición
  - **Y** muestra un mensaje de error indicando que ingrese un valor válido.

##### US011 · Eliminar celdas eléctricas registradas

- **E01: Deshabilitación exitosa de una celda eléctrica**
  - **Dado que** el Ingeniero de Planta selecciona una celda eléctrica que no tiene cátodos ni ánodos asignados
  - **Cuando** el Ingeniero de Planta confirma la deshabilitación
  - **Entonces** el sistema deshabilita la celda eléctrica.
- **E02: Deshabilitación de una celda con componentes asignados**
  - **Dado que** la celda eléctrica seleccionada tiene cátodos o ánodos asignados
  - **Cuando** el Ingeniero de Planta intenta deshabilitarla
  - **Entonces** el sistema rechaza la operación
  - **Y** muestra un mensaje indicando que la celda tiene componentes asignados.
- **E03: Liberación de componentes asignados a una celda para poder eliminarlos**
  - **Dado que** la celda eléctrica seleccionada tiene cátodos o ánodos asignados
  - **Cuando** el Ingeniero de Planta intenta deshabilitarla
  - **Y** selecciona la opción de liberar componentes
  - **Entonces** los cátodos y ánodos asignados a dicha celda quedan libres
  - **Y** el sistema deshabilita la celda eléctrica.

##### US012 · Registrar los cátodos y ánodos de cada celda

- **E01: Registro exitoso de cátodos y ánodos**
  - **Dado que** el Ingeniero de Planta ingresa los datos requeridos del cátodo y ánodo de una celda
  - **Cuando** el ingeniero confirma el registro
  - **Entonces** el sistema almacena los componentes asociados a la celda correspondiente.
- **E02: Registro con datos incompletos**
  - **Dado que** el Ingeniero de Planta no completa los campos obligatorios del cátodo o ánodo
  - **Cuando** intenta registrar el componente
  - **Entonces** el sistema rechaza el registro
  - **Y** muestra un mensaje indicando los campos faltantes.

##### US013 · Eliminar cátodos o ánodos registrados

- **E01: Deshabilitación exitosa de un cátodo o ánodo**
  - **Dado que** el cátodo o ánodo seleccionado no está en uso en ninguna celda activa
  - **Cuando** el Ingeniero de Planta selecciona la operación para deshabilitar un componente
  - **Entonces** el sistema deshabilita el componente.
- **E02: Deshabilitación de un componente en uso**
  - **Dado que** el cátodo o ánodo seleccionado está actualmente asignado a una celda
  - **Cuando** el Ingeniero de Planta intenta deshabilitarlo
  - **Entonces** el sistema rechaza la operación
  - **Y** muestra un mensaje indicando que el componente está en uso.

##### US014 · Intercambiar los cátodos y ánodos asignados en cada celda

- **E01: Intercambio exitoso de cátodos y ánodos**
  - **Dado que** el Ingeniero de Planta registra dos celdas que cuentan con cátodos o ánodos asignados
  - **Cuando** el Ingeniero de Planta solicita intercambiar los componentes entre ambas celdas
  - **Entonces** el sistema actualiza la asignación de los componentes en ambas celdas.
- **E02: Intercambio sin conexión**
  - **Dado que** el Ingeniero de Planta registra dos celdas que cuentan con cátodos o ánodos asignados
  - **Cuando** el Ingeniero de Planta intenta realizar el intercambio
  - **Y** no tiene conexión a internet
  - **Entonces** el sistema realiza la operación localmente
  - **Y** muestra un mensaje indicando que el cambio se sincronizará con el servidor cuando se recupere la conexión a internet.

##### US015 · Editar los datos de un cátodo o ánodo

- **E01: Edición exitosa de un cátodo o ánodo**
  - **Dado que** el Ingeniero de Planta registra un cátodo o ánodo en el sistema
  - **Cuando** el Ingeniero de Planta modifica sus datos y confirma los cambios
  - **Entonces** el sistema actualiza la información del componente.
- **E02: Edición con datos inválidos**
  - **Dado que** el Ingeniero de Planta ingresa un valor no válido en algún campo del componente
  - **Cuando** intenta editar y guardar los cambios
  - **Entonces** el sistema rechaza la edición
  - **Y** muestra un mensaje indicando que ingrese un valor válido.

##### US016 · Generar un código de barras sobre cada celda

- **E01: Generación exitosa del código de barras**
  - **Dado que** la celda eléctrica cuenta con un cátodo y un ánodo asignados
  - **Cuando** el Ingeniero de Planta solicita generar el código de barras de la celda
  - **Entonces** el sistema genera el código de barras correspondiente a dicha celda.
- **E02: Celda sin componentes asignados**
  - **Dado que** la celda eléctrica no cuenta con cátodo ni ánodo asignados
  - **Cuando** el Ingeniero de Planta intenta generar el código de barras
  - **Entonces** el sistema rechaza la generación
  - **Y** muestra un mensaje indicando que la celda no tiene componentes asignados.

##### US017 · Poder descargar el código de barras de cada celda

- **E01: Descarga exitosa del código de barras**
  - **Dado que** el código de barras de la celda ya ha sido generado
  - **Cuando** el Ingeniero de Planta solicita descargarlo
  - **Entonces** el sistema descarga el archivo del código de barras en formato de imagen.
- **E02: Código de barras no generado**
  - **Dado que** la celda eléctrica no cuenta con un código de barras generado
  - **Cuando** el Ingeniero de Planta intenta descargarlo
  - **Entonces** el sistema muestra un mensaje indicando que primero debe generar el código de barras.

#### Reglas de negocio

- Una celda solo puede tener **un cátodo y un ánodo** asignados.

### IAM Bounded Context

| ID    | Como                                       | Quiero                                                                                     | Para                                                                |
| ----- | ------------------------------------------ | ------------------------------------------------------------------------------------------ | ------------------------------------------------------------------- |
| US018 | Ingeniero Supervisor                       | visualizar peticiones de acceso a la aplicación                                            | revisarlas de manera rápida                                         |
| US019 | Ingeniero Supervisor                       | poder aprobar o rechazar peticiones de acceso                                              | controlar qué personal obtiene acceso al sistema                    |
| US020 | Ingeniero Supervisor                       | editar o deshabilitar cuentas de ingenieros integradas al sistema                          | asegurar que solo el personal autorizado mantenga acceso al sistema |
| US021 | Ingeniero Supervisor e Ingeniero de Planta | acceder al sistema con credenciales seguras                                                | usar el sistema sin problemas de seguridad                          |
| US022 | Supervisor e Ingeniero de Planta           | recuperar mi contraseña mediante un código de verificación enviado a mi correo electrónico | recuperar el acceso a mi cuenta de forma segura en caso de olvido   |
| US023 | Ingeniero de Planta                        | solicitar el registro de mi cuenta                                                         | poder solicitar el acceso al sistema                                |

#### Criterios de aceptación

##### US018 · Visualizar peticiones de acceso a la aplicación

- **E01: Visualización de peticiones de acceso**
  - **Dado que** existen peticiones de acceso pendientes de revisión
  - **Cuando** el Supervisor accede a la sección de peticiones de acceso
  - **Entonces** el sistema muestra la lista de peticiones pendientes.
- **E02: Sin peticiones pendientes**
  - **Dado que** no existen peticiones de acceso pendientes
  - **Cuando** el Supervisor accede a la sección de peticiones de acceso
  - **Entonces** el sistema muestra un mensaje indicando que no hay peticiones pendientes.

##### US019 · Poder aprobar o rechazar peticiones de acceso

- **E01: Aprobación exitosa de una petición de acceso**
  - **Dado que** existe una petición de acceso pendiente
  - **Cuando** el Supervisor aprueba la petición
  - **Entonces** el sistema habilita el acceso del solicitante
  - **Y** registra la petición como aprobada.
- **E02: Rechazo exitoso de una petición de acceso**
  - **Dado que** existe una petición de acceso pendiente
  - **Cuando** el Supervisor rechaza la petición
  - **Entonces** el sistema deniega el acceso del solicitante
  - **Y** registra la petición como rechazada.

##### US020 · Editar o deshabilitar cuentas de ingenieros integradas al sistema

- **E01: Edición exitosa de una cuenta**
  - **Dado que** la cuenta del ingeniero se encuentra registrada en el sistema
  - **Cuando** el Supervisor modifica los datos de la cuenta y confirma los cambios
  - **Entonces** el sistema actualiza la información de la cuenta.
- **E02: Deshabilitación exitosa de una cuenta**
  - **Dado que** la cuenta del ingeniero se encuentra activa en el sistema
  - **Cuando** el Supervisor deshabilita la cuenta
  - **Entonces** el sistema impide el acceso del ingeniero
  - **Y** marca la cuenta como deshabilitada.

##### US021 · Acceder al sistema con credenciales seguras

- **E01: Inicio de sesión exitoso**
  - **Dado que** el usuario cuenta con una cuenta activa en el sistema
  - **Cuando** ingresa sus credenciales correctas
  - **Entonces** el sistema concede el acceso y redirige al usuario a su panel principal.
- **E02: Credenciales incorrectas**
  - **Dado que** el usuario ingresa credenciales incorrectas
  - **Cuando** intenta iniciar sesión
  - **Entonces** el sistema rechaza el acceso
  - **Y** muestra un mensaje indicando que las credenciales son incorrectas.

##### US022 · Recuperar mi contraseña mediante un código de verificación enviado a mi correo electrónico

- **E01: Envío exitoso del código de verificación**
  - **Dado que** el usuario solicita recuperar su contraseña
  - **Cuando** ingresa su correo electrónico registrado
  - **Entonces** el sistema envía un código de verificación a dicho correo.
- **E02: Código incorrecto o expirado**
  - **Dado que** el usuario ha recibido un código de verificación
  - **Cuando** ingresa un código incorrecto o expirado
  - **Entonces** el sistema rechaza el intento
  - **Y** muestra un mensaje indicando que el código no es válido.

##### US023 · Solicitar el registro de mi cuenta

- **E01: Solicitud de registro enviada exitosamente**
  - **Dado que** el Ingeniero de Planta completa el formulario de solicitud de registro
  - **Cuando** confirma el envío de la solicitud
  - **Entonces** el sistema registra la solicitud
  - **Y** la deja disponible para revisión del Supervisor.
- **E02: Solicitud con datos incompletos**
  - **Dado que** el Ingeniero de Planta no completa todos los campos obligatorios del formulario
  - **Cuando** intenta enviar la solicitud
  - **Entonces** el sistema rechaza el envío
  - **Y** muestra un mensaje indicando los campos faltantes.

### Frontend Stack

- Flutter 3.47.4
- Dart 3.13.3

### Roles

1) Supervisor: ADMIN
2) Ingeniero de Planta: USER
